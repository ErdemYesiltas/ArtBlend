import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import 'overlay_bar.dart';
import 'studio_controller.dart';

/// Clone's controls: lock the source, Undo, Cancel, Apply. Size and
/// opacity come from the sidebar, as for any brush.
class CloneBar extends StatelessWidget {
  const CloneBar({super.key, required this.controller, required this.onApply});
  final StudioController controller;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final c = controller, l = AppLocalizations.of(context);
    final session = c.clone!;
    final enabled = !c.documentTransition;
    return OverlayBar(
      key: const ValueKey('clone-bar'),
      engaged: c.canvasEngaged,
      maxWidth: 480,
      children: [
        Row(
          children: [
            Text(l.clone, style: Theme.of(context).textTheme.labelLarge),
            barHint(l.cloneHint),
            const Spacer(),
            IconButton(
              key: const ValueKey('clone-lock'),
              tooltip: l.cloneLock,
              visualDensity: VisualDensity.compact,
              isSelected: session.locked,
              onPressed: enabled
                  ? () => c.setCloneLocked(!session.locked)
                  : null,
              icon: const Icon(Icons.lock_open, size: 20),
              selectedIcon: const Icon(Icons.lock, size: 20),
            ),
            IconButton(
              tooltip: l.undo,
              visualDensity: VisualDensity.compact,
              onPressed: enabled && session.strokes.isNotEmpty
                  ? c.undoClone
                  : null,
              icon: const Icon(Icons.undo, size: 20),
            ),
            IconButton(
              tooltip: l.cancel,
              visualDensity: VisualDensity.compact,
              onPressed: enabled ? c.cancelClone : null,
              icon: const Icon(Icons.close, size: 20),
            ),
            IconButton.filled(
              key: const ValueKey('clone-apply'),
              tooltip: l.apply,
              visualDensity: VisualDensity.compact,
              onPressed: enabled ? onApply : null,
              icon: const Icon(Icons.check, size: 20),
            ),
          ],
        ),
      ],
    );
  }
}
