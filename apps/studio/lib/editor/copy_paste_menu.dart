import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import 'studio_controller.dart';

/// Procreate's Copy & Paste menu: one row at the bottom of the canvas, by
/// the fingers that swiped it up.
class CopyPasteMenu extends StatelessWidget {
  const CopyPasteMenu({super.key, required this.controller, required this.run});
  final StudioController controller;

  /// Runs an action and reports its failure, as the editor does.
  final Future<void> Function(Future<void> Function()) run;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = controller;
    final editable = !c.document.activeLayer.locked;
    void act(Future<void> Function() action) {
      c.showCopyPasteMenu(false);
      run(action);
    }

    final actions = <(String, IconData, Future<void> Function()?)>[
      (l.cut, Icons.content_cut, editable ? c.cut : null),
      (l.copy, Icons.content_copy, () async => c.copy()),
      (l.copyAll, Icons.layers_outlined, () async => c.copy(all: true)),
      (
        l.duplicateLayer,
        Icons.control_point_duplicate,
        () => c.duplicateContent(
          c.selection == null
              ? l.layerCopy(c.document.activeLayer.name)
              : l.fromSelection,
        ),
      ),
      (
        l.cutAndPaste,
        Icons.drive_file_move_outline,
        editable ? () => c.cutAndPaste(l.fromSelection) : null,
      ),
      (
        l.paste,
        Icons.content_paste,
        c.clipboard == null ? null : () => c.paste(l.pastedLayer),
      ),
      (
        l.pastePrivately,
        Icons.shield_outlined,
        c.clipboard == null
            ? null
            : () => c.paste(l.pastedLayer, private: true),
      ),
    ];
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => c.showCopyPasteMenu(false),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Material(
              key: const ValueKey('copy-paste-menu'),
              elevation: 8,
              borderRadius: BorderRadius.circular(14),
              color: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Wrap(
                  spacing: 2,
                  children: [
                    for (final (label, icon, action) in actions)
                      TextButton(
                        onPressed: action == null ? null : () => act(action),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 20),
                            const SizedBox(height: 2),
                            Text(label, style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
