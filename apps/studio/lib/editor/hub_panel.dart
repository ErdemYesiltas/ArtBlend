import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:localhub_client/localhub_client.dart';
import 'package:material_ui/material_ui.dart';

import '../data/hub_service.dart';
import '../drawing/raster_cache.dart';
import '../l10n/app_localizations.dart';
import 'pairing_scanner.dart';
import 'studio_controller.dart';

const _hint = TextStyle(fontSize: 12, height: 1.6);
const _heading = TextStyle(fontWeight: FontWeight.w600);

String _hubError(Object error) => error is HubException
    ? error.message
    : error is CompanionRetired
    ? 'companion'
    : error.toString();

/// Local AI through LocalHub on the user's Mac. Pairing first; then a
/// status line, the generative bar's entry point, and the assistant, files
/// and MCP tools as tabs. Images are made on the canvas ([GenerativeBar]).
class HubPanel extends StatefulWidget {
  const HubPanel({super.key, required this.controller});
  final StudioController controller;

  @override
  State<HubPanel> createState() => _HubPanelState();
}

enum _Tab { assistant, files, mcp }

class _HubPanelState extends State<HubPanel> {
  _Tab tab = _Tab.assistant;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, hub = c.hub;
    return ListenableBuilder(
      listenable: hub,
      builder: (context, _) {
        final l = AppLocalizations.of(context);
        if (!hub.paired) return _Pairing(hub: hub);
        final images = hub.can('image.edit') || hub.can('image.create');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Status(hub: hub),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              key: const ValueKey('hub-open-generative'),
              onPressed: images
                  ? () {
                      c.setPanel(null);
                      c.hubJob.show();
                    }
                  : null,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(
                c.selection == null ? l.createImage : l.generativeFill,
              ),
            ),
            if (!images)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(l.hubNoImageWorkflow, style: _hint),
              ),
            const SizedBox(height: 14),
            SegmentedButton<_Tab>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                ButtonSegment(
                  value: _Tab.assistant,
                  label: Text(l.assistantTab),
                ),
                ButtonSegment(value: _Tab.files, label: Text(l.filesTab)),
                const ButtonSegment(value: _Tab.mcp, label: Text('MCP')),
              ],
              selected: {tab},
              onSelectionChanged: (value) => setState(() => tab = value.first),
            ),
            const SizedBox(height: 12),
            switch (tab) {
              _Tab.assistant =>
                hub.can('chat')
                    ? _Assistant(hub: hub)
                    : Text(
                        hub.scopes.contains('chat')
                            ? l.hubNoWorkflow
                            : l.hubPermissionMissing,
                        style: _hint,
                      ),
              _Tab.files => _Files(controller: c),
              _Tab.mcp => _Mcp(
                key: ValueKey(
                  hub.scopes.where((s) => s.startsWith('mcp:')).join(),
                ),
                controller: c,
              ),
            },
          ],
        );
      },
    );
  }
}

class _Pairing extends StatefulWidget {
  const _Pairing({required this.hub});
  final HubService hub;
  @override
  State<_Pairing> createState() => _PairingState();
}

class _PairingState extends State<_Pairing> {
  final address = TextEditingController(text: 'https://127.0.0.1:8790');
  final fingerprint = TextEditingController();
  final code = TextEditingController();
  final name = TextEditingController(
    text: Platform.isMacOS
        ? 'Mac'
        : Platform.isIOS
        ? 'iPad'
        : 'Android tablet',
  );
  String? failure;

  @override
  void dispose() {
    address.dispose();
    fingerprint.dispose();
    code.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> _pair(HubInvite invite) async {
    setState(() => failure = null);
    try {
      await widget.hub.pair(invite, deviceName: name.text);
    } catch (error) {
      if (mounted) setState(() => failure = _hubError(error));
    }
  }

  /// Fills the form from the QR and pairs at once; the fields show what was
  /// scanned and allow a retry.
  Future<void> _scan() async {
    final invite = await HubScannerPage.open(context);
    if (invite == null || !mounted) return;
    address.text = invite.address.toString();
    fingerprint.text = invite.fingerprint;
    code.text = invite.code;
    await _pair(invite);
  }

  Future<void> _typed() async {
    try {
      await _pair(
        HubInvite(
          address: hubAddress(address.text),
          fingerprint: normalizeFingerprint(fingerprint.text),
          code: code.text.trim(),
          version: 2,
        ),
      );
    } on FormatException catch (error) {
      setState(() => failure = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final busy = widget.hub.busy;
    final error = failure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.localHub, style: _heading),
        const SizedBox(height: 8),
        Text(l.hubHint, style: _hint),
        if (Platform.isIOS || Platform.isAndroid) ...[
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            key: const ValueKey('scan-pairing-qr'),
            onPressed: busy ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner, size: 18),
            label: Text(l.scanPairingQr),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: address,
          enabled: !busy,
          decoration: InputDecoration(labelText: l.serverUrl),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: fingerprint,
          enabled: !busy,
          maxLength: 95,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: l.fingerprint,
            hintText: 'SHA-256',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: code,
          enabled: !busy,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: l.pairingCode),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: name,
          enabled: !busy,
          maxLength: 80,
          decoration: InputDecoration(labelText: l.deviceName),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: busy ? null : _typed,
          child: Text(busy ? l.checking : l.pairDevice),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              error == 'companion'
                  ? l.companionRetired
                  : l.operationFailed(error),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.hub});
  final HubService hub;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final session = hub.session!;
    final down = [
      for (final i in hub.integrations)
        if (i['state'] != 'running') '${i['name'] ?? i['id']}',
    ];
    final healthy = hub.error == null && down.isEmpty;
    return Row(
      children: [
        Icon(
          Icons.circle,
          size: 10,
          color: healthy ? Colors.green : scheme.error,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.hubPaired(session.hubName ?? session.address.host),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (hub.error != null || down.isNotEmpty)
                Text(
                  hub.error != null
                      ? l.operationFailed(hub.error!)
                      : l.hubIntegrationsDown(down.join(', ')),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: scheme.error),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: l.refresh,
          visualDensity: VisualDensity.compact,
          onPressed: hub.refresh,
          icon: const Icon(Icons.refresh, size: 18),
        ),
        PopupMenuButton<void>(
          tooltip: l.localHub,
          icon: const Icon(Icons.more_vert, size: 18),
          itemBuilder: (_) => [
            PopupMenuItem(onTap: hub.unpair, child: Text(l.removePairing)),
          ],
        ),
      ],
    );
  }
}

/// Files on the hub: shared with the Mac and other paired apps.
class _Files extends StatefulWidget {
  const _Files({required this.controller});
  final StudioController controller;
  @override
  State<_Files> createState() => _FilesState();
}

class _FilesState extends State<_Files> {
  List<Map<String, Object?>>? files;
  String? failure;
  bool working = false;

  HubClient get client => widget.controller.hub.client;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (working) return;
    setState(() {
      working = true;
      failure = null;
    });
    try {
      await action();
    } catch (error) {
      failure = _hubError(error);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _load() => _guard(() async {
    final list = await client.files();
    list.sort(
      (a, b) => ((b['created_at'] as num?) ?? 0).compareTo(
        (a['created_at'] as num?) ?? 0,
      ),
    );
    files = list;
  });

  Future<void> _upload() => _guard(() async {
    final picked = await FilePicker.pickFile(type: FileType.image);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final extension = picked.extension?.toLowerCase();
    await client.uploadFile(
      bytes,
      picked.name,
      contentType: switch (extension) {
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'webp' => 'image/webp',
        _ => 'application/octet-stream',
      },
      purpose: 'reference',
    );
    files = await client.files();
  });

  Future<void> _uploadDrawing() => _guard(() async {
    final c = widget.controller;
    await c.settleStroke();
    final png = await renderDocumentPng(c.document, c.rasters.images);
    await client.uploadFile(
      png,
      '${c.document.name}.png',
      contentType: 'image/png',
      purpose: 'reference',
    );
    files = await client.files();
  });

  Future<void> _addToCanvas(Map<String, Object?> file) => _guard(() async {
    final bytes = await client.fileContent(file['id'] as String);
    await widget.controller.addImageLayer(
      bytes,
      (file['filename'] as String?) ?? 'LocalHub',
    );
  });

  Future<void> _delete(Map<String, Object?> file) => _guard(() async {
    await client.deleteFile(file['id'] as String);
    files = await client.files();
  });

  /// Thumbnails, fetched once per file.
  final _thumbs = <String, Future<Uint8List>>{};

  static bool _image(Map<String, Object?> file) =>
      (file['mime_type'] as String? ?? '').startsWith('image/') &&
      (file['bytes'] as num? ?? 0) <= 16 * 1024 * 1024;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final list = files;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(l.hubFiles, style: const TextStyle(fontSize: 12)),
            ),
            IconButton(
              tooltip: l.uploadFile,
              visualDensity: VisualDensity.compact,
              onPressed: working ? null : _upload,
              icon: const Icon(Icons.upload_file, size: 18),
            ),
            IconButton(
              tooltip: l.uploadDrawing,
              visualDensity: VisualDensity.compact,
              onPressed: working ? null : _uploadDrawing,
              icon: const Icon(Icons.brush_outlined, size: 18),
            ),
            IconButton(
              tooltip: l.refresh,
              visualDensity: VisualDensity.compact,
              onPressed: working ? null : _load,
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
        if (working) const LinearProgressIndicator(minHeight: 2),
        if (failure != null)
          Text(
            l.operationFailed(failure!),
            style: TextStyle(fontSize: 11, color: scheme.error),
          ),
        if (list != null && list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(l.noHubFiles, style: _hint),
          ),
        if (list != null && list.isNotEmpty)
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            padding: const EdgeInsets.only(top: 6),
            children: [
              for (final file in list)
                PopupMenuButton<void Function()>(
                  key: ValueKey('hub-file-${file['id']}'),
                  tooltip: (file['filename'] as String?) ?? '',
                  enabled: !working,
                  onSelected: (action) => action(),
                  itemBuilder: (_) => [
                    if (_image(file))
                      PopupMenuItem(
                        value: () => _addToCanvas(file),
                        child: Text(l.addToCanvas),
                      ),
                    PopupMenuItem(
                      value: () => _delete(file),
                      child: Text(l.deleteFile),
                    ),
                  ],
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_image(file))
                            FutureBuilder(
                              future: _thumbs.putIfAbsent(
                                file['id'] as String,
                                () => client.fileContent(file['id'] as String),
                              ),
                              builder: (context, snapshot) => snapshot.hasData
                                  ? Image.memory(
                                      snapshot.data!,
                                      fit: BoxFit.cover,
                                      cacheWidth: 200,
                                      errorBuilder: (_, _, _) =>
                                          const Icon(Icons.broken_image),
                                    )
                                  : const SizedBox.shrink(),
                            )
                          else
                            const Icon(Icons.insert_drive_file_outlined),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: ColoredBox(
                              color: Colors.black54,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                child: Text(
                                  (file['filename'] as String?) ??
                                      (file['id'] as String),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// The drawing assistant: a streamed chat with a model on the Mac.
class _Assistant extends StatefulWidget {
  const _Assistant({required this.hub});
  final HubService hub;
  @override
  State<_Assistant> createState() => _AssistantState();
}

class _AssistantState extends State<_Assistant> {
  final prompt = TextEditingController();
  final List<Map<String, String>> conversation = [];
  StreamSubscription<Map<String, Object?>>? reply;
  String? model, failure;

  @override
  void dispose() {
    unawaited(reply?.cancel());
    prompt.dispose();
    super.dispose();
  }

  void _send() {
    final text = prompt.text.trim();
    if (text.isEmpty || reply != null) return;
    final language = Localizations.localeOf(context).languageCode;
    final answer = <String, String>{'role': 'assistant', 'content': ''};
    setState(() {
      failure = null;
      conversation.add({'role': 'user', 'content': text});
      prompt.clear();
    });
    final messages = [
      {
        'role': 'system',
        'content':
            'You are a concise drawing and painting assistant. Suggest '
            'practical artistic techniques. You cannot see the canvas. '
            'Reply in the language the user writes in; if unsure, in '
            '${language == 'tr' ? 'Turkish' : 'English'}.',
      },
      ...conversation.skip(math.max(0, conversation.length - 20)),
    ];
    conversation.add(answer);
    reply = widget.hub.client
        // The hub needs a model for chat: the chosen one or the first.
        .chatStream({
          'model': model ?? widget.hub.modelsFor('chat').first['id'],
          'messages': messages,
        })
        .listen(
          (chunk) {
            // A provider failing mid-stream (e.g. out of GPU memory) sends
            // an error chunk instead of choices.
            final error = chunk['error'];
            if (error != null && mounted) {
              setState(
                () => failure = error is Map
                    ? '${error['message'] ?? error}'
                    : '$error',
              );
              return;
            }
            final choices = chunk['choices'];
            final delta = choices is List && choices.isNotEmpty
                ? (choices.first as Map)['delta']
                : null;
            final content = delta is Map ? delta['content'] : null;
            if (content is String && mounted) {
              setState(() => answer['content'] = answer['content']! + content);
            }
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              failure = _hubError(error);
              reply = null;
              if (answer['content']!.isEmpty) conversation.remove(answer);
            });
          },
          onDone: () {
            if (!mounted) return;
            setState(() {
              reply = null;
              if (answer['content']!.isEmpty) conversation.remove(answer);
            });
          },
        );
  }

  Future<void> _stop() async {
    await reply?.cancel();
    if (mounted) setState(() => reply = null);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ids = [
      for (final m in widget.hub.modelsFor('chat')) m['id'] as String,
    ];
    if (model != null && !ids.contains(model)) model = null;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ids.length > 1)
          DropdownButtonFormField<String>(
            initialValue: model ?? ids.first,
            isExpanded: true,
            decoration: InputDecoration(labelText: l.model),
            items: [
              for (final id in ids)
                DropdownMenuItem(
                  value: id,
                  child: Text(id, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: reply != null
                ? null
                : (value) => setState(() => model = value),
          ),
        for (final message in conversation)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Material(
              color: message['role'] == 'user'
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: SelectableText(
                  message['content']!.isEmpty ? '…' : message['content']!,
                  style: const TextStyle(fontSize: 12, height: 1.6),
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        TextField(
          controller: prompt,
          minLines: 1,
          maxLines: 4,
          maxLength: 4000,
          enabled: reply == null,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _send(),
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            hintText: l.askAssistant,
            suffixIcon: reply == null
                ? IconButton(
                    tooltip: l.send,
                    onPressed: _send,
                    icon: const Icon(Icons.arrow_upward, size: 18),
                  )
                : IconButton(
                    tooltip: l.stop,
                    onPressed: _stop,
                    icon: const Icon(Icons.stop, size: 18),
                  ),
          ),
        ),
        if (failure != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l.operationFailed(failure!),
              style: TextStyle(fontSize: 11, color: scheme.error),
            ),
          ),
        const SizedBox(height: 6),
        Text(l.chatPrivacy, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}

/// MCP tools the Mac allowed this device: pick one, give its arguments as
/// JSON, run it. Images it returns can become layers.
class _Mcp extends StatefulWidget {
  const _Mcp({super.key, required this.controller});
  final StudioController controller;
  @override
  State<_Mcp> createState() => _McpState();
}

class _McpState extends State<_Mcp> {
  final arguments = TextEditingController(text: '{}');
  List<Map<String, Object?>> servers = const [], tools = const [];
  String? server, tool, failure;
  bool working = false;
  Map<String, Object?>? result;

  HubClient get client => widget.controller.hub.client;

  @override
  void initState() {
    super.initState();
    unawaited(_guard(() async => servers = await client.mcpServers()));
  }

  @override
  void dispose() {
    arguments.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    setState(() {
      working = true;
      failure = null;
    });
    try {
      await action();
    } catch (error) {
      failure = _hubError(error);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  void _pickServer(String? id) {
    setState(() {
      server = id;
      tool = null;
      tools = const [];
      result = null;
    });
    if (id != null) {
      unawaited(_guard(() async => tools = await client.mcpTools(id)));
    }
  }

  /// Starts the arguments from the tool's schema: its required fields, empty.
  void _pickTool(String? name) {
    final schema = tools.firstWhere((t) => t['name'] == name)['inputSchema'];
    final properties = schema is Map ? schema['properties'] : null;
    final required = schema is Map ? schema['required'] : null;
    final template = <String, Object?>{
      if (properties is Map && required is List)
        for (final key in required)
          if (properties[key] case final Map property)
            '$key': switch (property['type']) {
              'number' || 'integer' => 0,
              'boolean' => false,
              'array' => const [],
              'object' => const <String, Object?>{},
              _ => '',
            },
    };
    setState(() {
      tool = name;
      result = null;
      arguments.text = const JsonEncoder.withIndent('  ').convert(template);
    });
  }

  Future<void> _run() => _guard(() async {
    final input = jsonDecode(arguments.text);
    if (input is! Map) {
      throw const FormatException('Arguments must be a JSON object');
    }
    result = await client.mcpCall(
      server!,
      tool!,
      input.cast<String, Object?>(),
    );
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final selected = tools.where((t) => t['name'] == tool).firstOrNull;
    final content = (result?['content'] as List?) ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!working && servers.isEmpty && failure == null)
          Text(l.noMcpServers, style: _hint),
        if (servers.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: server,
            isExpanded: true,
            decoration: InputDecoration(labelText: l.mcpServer),
            items: [
              for (final s in servers)
                DropdownMenuItem(
                  value: s['id'] as String,
                  child: Text(s['id'] as String),
                ),
            ],
            onChanged: working ? null : _pickServer,
          ),
        if (tools.isNotEmpty) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: tool,
            isExpanded: true,
            decoration: InputDecoration(labelText: l.mcpTool),
            items: [
              for (final t in tools)
                DropdownMenuItem(
                  value: t['name'] as String,
                  child: Text(
                    t['name'] as String,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: working ? null : _pickTool,
          ),
        ],
        if (selected != null) ...[
          if (selected['description'] case final String description)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(description, style: const TextStyle(fontSize: 11)),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: arguments,
            minLines: 3,
            maxLines: 10,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(labelText: l.mcpArguments),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: working ? null : _run,
            child: Text(l.runTool),
          ),
        ],
        if (working) const LinearProgressIndicator(),
        if (failure != null)
          Text(
            l.operationFailed(failure!),
            style: TextStyle(fontSize: 11, color: scheme.error),
          ),
        for (final item in content.whereType<Map>())
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: switch (item['type']) {
              'image' when item['data'] is String => _McpImage(
                bytes: base64Decode(item['data'] as String),
                controller: widget.controller,
                name: tool ?? 'MCP',
              ),
              _ => SelectableText(
                '${item['text'] ?? jsonEncode(item)}',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: result?['isError'] == true ? scheme.error : null,
                ),
              ),
            },
          ),
      ],
    );
  }
}

class _McpImage extends StatelessWidget {
  const _McpImage({
    required this.bytes,
    required this.controller,
    required this.name,
  });
  final Uint8List bytes;
  final StudioController controller;
  final String name;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(bytes, cacheWidth: 600),
      ),
      const SizedBox(height: 6),
      FilledButton.tonal(
        onPressed: () => unawaited(controller.addImageLayer(bytes, name)),
        child: Text(AppLocalizations.of(context).addImageLayer),
      ),
    ],
  );
}
