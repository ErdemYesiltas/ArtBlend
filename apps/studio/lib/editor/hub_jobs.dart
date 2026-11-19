import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:localhub_client/localhub_client.dart';

import '../data/hub_service.dart';
import '../domain/ai_canvas_input.dart';
import '../domain/selection.dart';

/// A hub job's state as the bar shows it.
enum HubJobState {
  idle,
  submitting,
  queued,
  running,
  completed,
  failed,
  cancelled,
}

/// Puts a result on the canvas: a new layer, or over [replace] (another
/// variation of the same generation). Returns the layer id.
typedef PlaceImage = Future<String> Function(
  Uint8List image,
  AiCanvasInput? source,
  String? replace,
);

/// Generative fill and image generation through the hub, as in Photoshop:
/// each generation becomes one layer right away (masked by the selection
/// for a fill), more variations swap that layer's pixels, and the user keeps
/// it ([done]) or drops it ([discard]). Owned by the studio, so closing the
/// panel keeps it; the hub runs jobs asynchronously and reports over SSE.
class HubImageJob extends ChangeNotifier {
  HubImageJob(
    this.hub, {
    required this.place,
    required this.remove,
    this.save,
    this.saved,
  }) {
    hub.addListener(_pairingChanged);
  }
  final HubService hub;
  final PlaceImage place;
  final void Function(String layerId) remove;

  /// Keeps the job in flight across app restarts (null forgets it), and
  /// reads it back; the hub keeps running it meanwhile.
  final void Function(Map<String, Object?>? job)? save;
  final Map<String, Object?>? Function()? saved;
  bool _resumeTried = false;

  /// Without a prompt, fill continues what surrounds the selection.
  static const contextPrompt =
      'Fill the masked area so it blends seamlessly with the surrounding '
      'image, matching its style, lighting and colors.';

  /// The bar is showing.
  bool open = false;

  HubJobState state = HubJobState.idle;
  String? jobId, error;

  /// 0…1 when the hub knows it.
  double? progress;

  /// What the hub is doing: the current node or why it waits (memory).
  String? detail;

  /// Jobs ahead in ComfyUI while queued; the hub's estimate of time left.
  int? queuePosition, etaSeconds;

  /// The area and selection a fill was made from; null for a new image.
  AiCanvasInput? source;

  /// Every result of this generation and the one on the canvas.
  List<Uint8List> variations = const [];
  int selected = 0;

  /// The layer holding the selected variation.
  String? layerId;

  /// What was asked, shown while a generation is open.
  String? prompt;

  Future<Map<String, Object?>> Function(int seed)? _again;
  int? _fixedSeed;
  int _epoch = 0;
  bool _disposed = false;
  StreamSubscription<Map<String, Object?>>? _events;
  final _random = math.Random();

  bool get busy =>
      state == HubJobState.submitting ||
      state == HubJobState.queued ||
      state == HubJobState.running;

  /// A generation is open: its layer is on the canvas, not yet kept.
  bool get pending => layerId != null;

  /// More variations can be asked (not after a restart: the request is gone).
  bool get canVary => _again != null;

  /// Picks up a job sent before the app closed: follows it on the hub and
  /// puts its result where it was asked for.
  Future<void> resume() async {
    final job = saved?.call();
    if (busy || pending || job == null) return;
    final id = job['id'], source = job['source'];
    if (id is! String) {
      save?.call(null);
      return;
    }
    _reset();
    final epoch = _epoch;
    jobId = id;
    prompt = job['prompt'] as String?;
    try {
      this.source = source is Map
          ? _sourceFromJson(source.cast<String, Object?>())
          : null;
    } on Object {
      save?.call(null);
      return;
    }
    state = HubJobState.queued;
    open = true;
    _notify();
    try {
      final snapshot = await hub.client.job(id);
      if (!_current(epoch)) return;
      _apply(snapshot);
      if (busy) {
        _follow(id, epoch);
      } else {
        await _finish(snapshot, epoch);
      }
    } on HubException catch (e) {
      // Gone from the hub (expired or deleted): nothing to wait for.
      if (e.status == 404) {
        save?.call(null);
        if (_current(epoch)) {
          _reset();
          open = false;
          _notify();
        }
      } else if (_current(epoch)) {
        _fail(e);
      }
    } catch (e) {
      if (_current(epoch)) _fail(e);
    }
  }

  void show() {
    open = true;
    _notify();
  }

  /// Hides the bar; a running job and a pending layer stay.
  void hide() {
    open = false;
    _notify();
  }

  /// Fills the selection [capture] reads (it runs here, so the bar shows
  /// progress and errors from the start).
  Future<void> fill(
    Future<AiCanvasInput> Function() capture, {
    String prompt = '',
    String? negativePrompt,
    double strength = 1,
    int? seed,
    int? steps,
    String? model,
  }) async {
    if (busy) return;
    _start(prompt, seed);
    final epoch = _epoch;
    try {
      final input = await capture();
      if (!_current(epoch)) return;
      source = input;
      final text = prompt.trim().isEmpty ? contextPrompt : prompt.trim();
      _again = (seed) => hub.client.editImage(
        {
          'prompt': text,
          'negative_prompt': ?negativePrompt,
          'strength': strength,
          'seed': seed,
          'steps': ?steps,
          'model': ?model,
        },
        image: HubInput.bytes(input.png, filename: 'canvas.png'),
        async: true,
      );
    } catch (e) {
      if (_current(epoch)) _fail(e);
      return;
    }
    await _run(epoch);
  }

  /// A new image from [prompt], [width] × [height].
  Future<void> create({
    required String prompt,
    required int width,
    required int height,
    String? negativePrompt,
    int? seed,
    int? steps,
    String? model,
  }) async {
    if (busy) return;
    _start(prompt, seed);
    _again = (seed) => hub.client.generateImage({
      'prompt': prompt.trim(),
      'size': '${width}x$height',
      'negative_prompt': ?negativePrompt,
      'seed': seed,
      'steps': ?steps,
      'model': ?model,
    }, async: true);
    await _run(_epoch);
  }

  /// One more variation of the same request (same area, new seed).
  Future<void> more() async {
    if (busy || _again == null) return;
    _beginJob();
    await _run(_epoch);
  }

  /// Shows variation [index] on the canvas.
  Future<void> select(int index) async {
    if (busy || index < 0 || index >= variations.length) return;
    final epoch = _epoch;
    selected = index;
    _notify();
    try {
      final id = await place(variations[index], source, layerId);
      if (_current(epoch)) layerId = id;
    } catch (e) {
      if (_current(epoch)) _fail(e);
    }
    _notify();
  }

  /// Keeps the layer as it is and closes the generation.
  void done() {
    if (busy) return;
    _reset();
    open = false;
    _notify();
  }

  /// Removes the generation's layer and closes it.
  void discard() {
    if (busy) return;
    final id = layerId;
    _reset();
    if (id != null) remove(id);
    _notify();
  }

  /// Stops the job on the Mac (ComfyUI interrupts it).
  Future<void> cancel() async {
    final id = jobId;
    if (id == null || !busy) return;
    try {
      _apply(await hub.client.cancelJob(id));
    } catch (e) {
      error = e.toString();
      _notify();
    }
  }

  void _start(String prompt, int? seed) {
    _reset();
    this.prompt = prompt.trim();
    _fixedSeed = seed;
    _beginJob();
  }

  void _beginJob() {
    unawaited(_events?.cancel());
    _events = null;
    state = HubJobState.submitting;
    jobId = error = detail = null;
    progress = null;
    queuePosition = etaSeconds = null;
    _notify();
  }

  Future<void> _run(int epoch) async {
    final again = _again;
    if (again == null || !_current(epoch)) return;
    // A fixed seed still varies per variation; otherwise every run is new.
    final seed = _fixedSeed == null
        ? _random.nextInt(1 << 31)
        : _fixedSeed! + variations.length;
    try {
      final job = await again(seed);
      if (!_current(epoch)) return;
      _apply(job);
      final id = jobId;
      if (id == null) throw const FormatException('The hub returned no job');
      if (busy) {
        save?.call({
          'id': id,
          'prompt': ?prompt,
          if (source case final source?) 'source': _sourceToJson(source),
        });
        _follow(id, epoch);
      } else {
        await _finish(job, epoch);
      }
    } catch (e) {
      if (_current(epoch)) _fail(e);
    }
  }

  void _follow(String id, int epoch) {
    _events = hub.client
        .jobEvents(id)
        .listen(
          (snapshot) {
            if (_current(epoch)) unawaited(_snapshot(snapshot, epoch));
          },
          onError: (Object e) {
            if (_current(epoch) && busy) _fail(e);
          },
        );
  }

  Future<void> _snapshot(Map<String, Object?> job, int epoch) async {
    _apply(job);
    if (!busy) await _finish(job, epoch);
    _notify();
  }

  void _apply(Map<String, Object?> job) {
    jobId = job['id'] as String? ?? jobId;
    final progress = job['progress'];
    this.progress = progress is num ? progress.toDouble() : this.progress;
    final waiting = job['waiting_reason'] as String?;
    final node = job['current_node'] as String?;
    final position = job['queue_position'], eta = job['eta_seconds'];
    detail = waiting ?? node;
    queuePosition = position is int && position > 0 ? position : null;
    etaSeconds = eta is int && eta > 0 ? eta : null;
    state = switch (job['status']) {
      'queued' => HubJobState.queued,
      'in_progress' => HubJobState.running,
      'completed' => HubJobState.completed,
      'cancelled' => HubJobState.cancelled,
      'failed' => HubJobState.failed,
      _ => state,
    };
    if (state == HubJobState.failed) error = job['error'] as String?;
    _notify();
  }

  Future<void> _finish(Map<String, Object?> job, int epoch) async {
    await _events?.cancel();
    _events = null;
    save?.call(null);
    if (state != HubJobState.completed) return;
    final ids = (job['output_file_ids'] as List? ?? const []).cast<String>();
    try {
      final images = [for (final id in ids) await hub.client.fileContent(id)];
      if (!_current(epoch)) return;
      if (images.isEmpty) throw const FormatException('The job made no image');
      variations = [...variations, ...images];
      selected = variations.length - 1;
      final id = await place(variations[selected], source, layerId);
      if (!_current(epoch)) return;
      layerId = id;
    } catch (e) {
      if (_current(epoch)) _fail(e);
      return;
    }
    _notify();
  }

  void _fail(Object e) {
    save?.call(null);
    state = HubJobState.failed;
    error = e is HubException ? e.message : e.toString();
    unawaited(_events?.cancel());
    _events = null;
    _notify();
  }

  void _reset() {
    _epoch++;
    unawaited(_events?.cancel());
    _events = null;
    state = HubJobState.idle;
    jobId = error = detail = prompt = null;
    progress = null;
    queuePosition = etaSeconds = _fixedSeed = null;
    source = null;
    variations = const [];
    selected = 0;
    layerId = null;
    _again = null;
  }

  void _pairingChanged() {
    if (!hub.paired && busy) {
      _reset();
      _notify();
    }
    if (hub.paired && !_resumeTried) {
      _resumeTried = true;
      unawaited(resume());
    }
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    unawaited(_events?.cancel());
    hub.removeListener(_pairingChanged);
    super.dispose();
  }
}

Map<String, Object?> _sourceToJson(AiCanvasInput s) => {
  'documentId': s.documentId,
  'revision': s.revision,
  'layerId': s.layerId,
  'width': s.width,
  'height': s.height,
  'area': [s.area.left, s.area.top, s.area.right, s.area.bottom],
  if (s.selection case final selection?) 'selection': selection.toJson(),
};

/// The placement of a restored job; its pixels were sent and are not kept.
AiCanvasInput _sourceFromJson(Map<String, Object?> json) {
  final area = (json['area'] as List).cast<num>();
  final selection = json['selection'];
  return AiCanvasInput(
    documentId: json['documentId'] as String,
    revision: json['revision'] as int,
    layerId: json['layerId'] as String,
    png: Uint8List(0),
    width: json['width'] as int,
    height: json['height'] as int,
    area: Rect.fromLTRB(
      area[0].toDouble(),
      area[1].toDouble(),
      area[2].toDouble(),
      area[3].toDouble(),
    ),
    selection: selection is Map
        ? SelectionRegion.fromJson(selection.cast<String, dynamic>())
        : null,
  );
}

/// Turns a few keywords into a detailed English prompt with the hub's chat
/// model, yielding the prompt as it streams. Thinking blocks, labels and
/// quotes some models add are left out.
Stream<String> writeImagePrompt(
  HubClient client,
  String keywords, {
  required bool fill,
  required String model,
  Uint8List? image,
}) async* {
  final messages = [
    {
      'role': 'system',
      'content':
          'You write prompts for an image generation model. Turn the '
          "user's keywords into one detailed prompt in English: subject, "
          'setting, composition, lighting, colors, style and medium, in '
          'natural sentences, about 40 to 80 words. Keep every idea the '
          'user gave, translate them if needed, and add no text, logos or '
          'watermarks.${fill ? ' The image is painted into a selected area '
                    'of an existing drawing and must blend with what '
                    'surrounds it: describe what appears there, not a whole '
                    'new scene.' : ''} Reply with the prompt only: no '
          'title, quotes, lists or explanations.',
    },
    {
      'role': 'user',
      'content': image == null
          ? keywords
          : [
              {
                'type': 'text',
                'text':
                    '$keywords\n\nThe image shows the drawing; the area '
                    'outlined in magenta is where the new content goes. '
                    'Match the drawing\'s style and lighting, and do not '
                    'mention the outline.',
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/png;base64,${base64Encode(image)}',
                },
              },
            ],
    },
  ];
  var text = '';
  await for (final chunk in client.chatStream({
    'model': model,
    'messages': messages,
    'temperature': .7,
    // Reasoning models think before answering; a tight limit ends the
    // reply in the thinking and leaves no prompt.
    'max_tokens': 4096,
  })) {
    final error = chunk['error'];
    if (error != null) {
      throw StateError(
        error is Map ? '${error['message'] ?? error}' : '$error',
      );
    }
    final choices = chunk['choices'];
    final delta = choices is List && choices.isNotEmpty
        ? (choices.first as Map)['delta']
        : null;
    final content = delta is Map ? delta['content'] : null;
    if (content is! String || content.isEmpty) continue;
    text += content;
    final prompt = cleanImagePrompt(text);
    if (prompt.isNotEmpty) yield prompt;
  }
  if (cleanImagePrompt(text).isEmpty) {
    throw StateError(
      'The model returned no prompt (it may have spent its answer thinking)',
    );
  }
}

/// The prompt alone: without `<think>` blocks (finished or still open), a
/// "Prompt:" label or surrounding quotes.
String cleanImagePrompt(String text) => text
    .replaceAll(RegExp(r'<think>[\s\S]*?(</think>|$)'), '')
    .trim()
    .replaceFirst(
      RegExp(r'^[*_\s]*prompt[*_\s]*:[*_\s]*', caseSensitive: false),
      '',
    )
    .replaceAll(RegExp(r'^["“]+|["”]+$'), '')
    .trim();
