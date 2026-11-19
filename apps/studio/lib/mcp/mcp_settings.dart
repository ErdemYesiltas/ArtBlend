import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import 'mcp_service.dart';

/// The settings panel's MCP section: on/off, network reach, the line that
/// adds ArtBlend to Claude Code, and a new key.
class McpSettings extends StatelessWidget {
  const McpSettings({super.key, required this.service});
  final McpService service;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hint = TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.mcpTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
          SwitchListTile.adaptive(
            key: const ValueKey('mcp-enabled'),
            contentPadding: EdgeInsets.zero,
            title: Text(l.mcpServer, style: const TextStyle(fontSize: 13)),
            value: service.enabled,
            onChanged: service.setEnabled,
          ),
          SwitchListTile.adaptive(
            key: const ValueKey('mcp-lan'),
            contentPadding: EdgeInsets.zero,
            title: Text(l.mcpLan, style: const TextStyle(fontSize: 13)),
            value: service.lan,
            onChanged: service.setLan,
          ),
          if (service.error case final error?)
            Text(
              l.mcpError(error),
              style: hint.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          if (service.running) ...[
            Text(l.mcpAdd, style: hint),
            for (final command in service.commands)
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      command,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l.copy,
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: command)),
                  ),
                ],
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.key, size: 18),
                label: Text(l.mcpNewKey),
                onPressed: service.renewToken,
              ),
            ),
          ],
          Text(l.mcpHint, style: hint),
        ],
      ),
    );
  }
}

/// Over every screen while an agent works: which tool it is running.
class McpBanner extends StatelessWidget {
  const McpBanner({super.key, required this.activity});
  final ValueListenable<String?> activity;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: activity,
    builder: (context, String? tool, _) {
      final scheme = Theme.of(context).colorScheme;
      return IgnorePointer(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: AnimatedOpacity(
              opacity: tool == null ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: tool == null
                  ? const SizedBox.shrink()
                  : Material(
                      key: const ValueKey('mcp-banner'),
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(16),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.smart_toy_outlined,
                              size: 16,
                              color: scheme.onTertiaryContainer,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              AppLocalizations.of(context).mcpWorking(tool),
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onTertiaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ),
      );
    },
  );
}
