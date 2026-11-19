import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import 'hub_jobs.dart';
import 'studio_controller.dart';

/// Photoshop-style contextual bar for generative fill (with a selection) and
/// image generation (without one): one line to ask, one line while the Mac
/// works, one line to flip through variations and keep or drop the layer.
class GenerativeBar extends StatefulWidget {
  const GenerativeBar({super.key, required this.controller});
  final StudioController controller;

  @override
  State<GenerativeBar> createState() => _GenerativeBarState();
}

class _GenerativeBarState extends State<GenerativeBar> {
  final prompt = TextEditingController();
  final negative = TextEditingController();
  final seed = TextEditingController();
  final steps = TextEditingController();
  double strength = 1;
  String? model;
  bool settings = false;

  /// Writing a prompt from the keywords in the field.
  StreamSubscription<String>? writing;
  String? writeError;

  StudioController get c => widget.controller;
  HubImageJob get job => c.hubJob;

  @override
  void dispose() {
    unawaited(writing?.cancel());
    prompt.dispose();
    negative.dispose();
    seed.dispose();
    steps.dispose();
    super.dispose();
  }

  bool get filling => c.selection != null;

  void _write() {
    final keywords = prompt.text.trim();
    if (keywords.isEmpty || writing != null) return;
    final before = prompt.text;
    void finish() {
      if (mounted) setState(() => writing = null);
    }

    setState(() {
      writeError = null;
      writing = _promptStream(keywords).listen(
        (text) {
          prompt.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
        },
        onError: (Object error) {
          prompt.text = before;
          writeError = error is StateError ? error.message : '$error';
          finish();
        },
        onDone: finish,
        cancelOnError: true,
      );
    });
  }

  /// With a selection, the model also sees the area (if it reads images;
  /// otherwise it is asked again with words only).
  Stream<String> _promptStream(String keywords) async* {
    final model = c.hub.modelsFor('chat').first['id'] as String;
    final image = filling ? await c.captureSelectionPreview() : null;
    if (image != null) {
      var wrote = false;
      try {
        await for (final text in writeImagePrompt(
          c.hub.client,
          keywords,
          fill: true,
          model: model,
          image: image,
        )) {
          wrote = true;
          yield text;
        }
        return;
      } catch (_) {
        if (wrote) rethrow;
      }
    }
    yield* writeImagePrompt(
      c.hub.client,
      keywords,
      fill: filling,
      model: model,
    );
  }

  Future<void> _stopWriting() async {
    await writing?.cancel();
    if (mounted) setState(() => writing = null);
  }

  String get capability => filling ? 'image.edit' : 'image.create';

  void _generate() {
    final text = prompt.text.trim();
    if (!filling && text.isEmpty) return;
    final negativePrompt = negative.text.trim().isEmpty
        ? null
        : negative.text.trim();
    final seedValue = int.tryParse(seed.text.trim());
    final stepsValue = int.tryParse(steps.text.trim());
    setState(() => settings = false);
    if (filling) {
      unawaited(
        job.fill(
          c.captureGenerativeFill,
          prompt: text,
          negativePrompt: negativePrompt,
          strength: strength,
          seed: seedValue,
          steps: stepsValue,
          model: model,
        ),
      );
    } else {
      // Image models work at about a megapixel: keep the canvas's shape.
      final dims = c.document.dimensions;
      final scale = math.sqrt(1024 * 1024 / (dims.width * dims.height));
      int snap(double v) => math.max(64, (v * scale / 64).round() * 64);
      unawaited(
        job.create(
          prompt: text,
          width: snap(dims.width.toDouble()),
          height: snap(dims.height.toDouble()),
          negativePrompt: negativePrompt,
          seed: seedValue,
          steps: stepsValue,
          model: model,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([job, c.hub]),
      builder: (context, _) {
        final Widget body;
        if (job.busy) {
          body = _progress(l);
        } else if (job.pending) {
          body = _variations(l);
        } else {
          body = _ask(l);
        }
        final error = job.error;
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Material(
                key: const ValueKey('generative-bar'),
                elevation: 8,
                color: scheme.surface,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      body,
                      if (job.state == HubJobState.cancelled)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                          child: Text(
                            l.jobCancelled,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                          child: Text(
                            l.operationFailed(error),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: scheme.error),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _ask(AppLocalizations l) {
    final hub = c.hub;
    if (!hub.can(capability)) {
      return Row(
        children: [
          const Icon(Icons.auto_awesome, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hub.scopes.contains(capability)
                  ? l.hubNoWorkflow
                  : l.hubPermissionMissing,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          _close(l),
        ],
      );
    }
    final ids = [for (final m in hub.modelsFor(capability)) m['id'] as String];
    if (model != null && !ids.contains(model)) model = null;
    final ready = filling || prompt.text.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Tooltip(
              message: filling ? l.generativeFill : l.createImage,
              child: const Icon(Icons.auto_awesome, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                key: const ValueKey('generative-prompt'),
                controller: prompt,
                autofocus: true,
                maxLength: 4000,
                minLines: 1,
                maxLines: 4,
                readOnly: writing != null,
                textInputAction: TextInputAction.go,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _generate(),
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  border: InputBorder.none,
                  hintText: filling ? l.fillPromptHint : l.imagePrompt,
                ),
              ),
            ),
            if (hub.can('chat'))
              writing == null
                  ? IconButton(
                      key: const ValueKey('generative-write'),
                      tooltip: l.writePrompt,
                      onPressed: prompt.text.trim().isEmpty ? null : _write,
                      icon: const Icon(Icons.auto_fix_high, size: 20),
                    )
                  : IconButton(
                      tooltip: l.stop,
                      onPressed: _stopWriting,
                      icon: const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
            IconButton(
              tooltip: l.generationSettings,
              isSelected: settings,
              onPressed: () => setState(() => settings = !settings),
              icon: const Icon(Icons.tune, size: 20),
            ),
            const SizedBox(width: 4),
            FilledButton(
              key: const ValueKey('generative-run'),
              onPressed: ready && writing == null ? _generate : null,
              child: Text(l.generate),
            ),
            _close(l),
          ],
        ),
        if (writeError case final error?)
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 0, 8, 4),
            child: Text(
              l.operationFailed(error),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        if (settings)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (ids.length > 1)
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String?>(
                      initialValue: model,
                      isExpanded: true,
                      isDense: true,
                      decoration: InputDecoration(labelText: l.model),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(l.hubDefaultModel),
                        ),
                        for (final id in ids)
                          DropdownMenuItem(
                            value: id,
                            child: Text(id, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (value) => setState(() => model = value),
                    ),
                  ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: negative,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: l.negativePrompt,
                    ),
                  ),
                ),
                for (final (field, label) in [(seed, l.seed), (steps, l.steps)])
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: field,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: label,
                      ),
                    ),
                  ),
                if (filling)
                  SizedBox(
                    width: 220,
                    child: Row(
                      children: [
                        Text(
                          '${l.denoise} ${(strength * 100).round()}%',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Expanded(
                          child: Slider(
                            value: strength,
                            onChanged: (v) => setState(() => strength = v),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _progress(AppLocalizations l) {
    final status = [
      job.state == HubJobState.running ? l.jobRunning : l.jobQueued,
      ?job.detail,
      if (job.queuePosition case final ahead?) l.jobsAhead(ahead),
      if (job.etaSeconds case final eta?)
        l.aboutMinutes(math.max(1, (eta / 60).round())),
    ].join(' · ');
    return Row(
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            value: job.progress == null || job.progress == 0
                ? null
                : job.progress,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            status,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        TextButton(
          onPressed: job.state == HubJobState.submitting ? null : job.cancel,
          child: Text(l.stop),
        ),
      ],
    );
  }

  Widget _variations(AppLocalizations l) {
    final count = job.variations.length;
    return Row(
      children: [
        IconButton(
          tooltip: l.previousVariation,
          onPressed: job.selected > 0
              ? () => unawaited(job.select(job.selected - 1))
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Text(
          '${job.selected + 1} / $count',
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
        IconButton(
          tooltip: l.nextVariation,
          onPressed: job.selected < count - 1
              ? () => unawaited(job.select(job.selected + 1))
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
        Expanded(
          child: Text(
            job.prompt?.isNotEmpty == true ? job.prompt! : l.generativeFill,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        IconButton(
          key: const ValueKey('generative-more'),
          tooltip: l.newVariation,
          onPressed: job.canVary ? () => unawaited(job.more()) : null,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: l.discard,
          onPressed: job.discard,
          icon: const Icon(Icons.delete_outline),
        ),
        const SizedBox(width: 4),
        FilledButton(
          key: const ValueKey('generative-done'),
          onPressed: job.done,
          child: Text(l.done),
        ),
      ],
    );
  }

  Widget _close(AppLocalizations l) => IconButton(
    tooltip: l.close,
    onPressed: job.hide,
    icon: const Icon(Icons.close, size: 20),
  );
}
