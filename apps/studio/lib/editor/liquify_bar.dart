import 'package:material_ui/material_ui.dart';

import '../drawing/liquify.dart';
import '../l10n/app_localizations.dart';
import 'overlay_bar.dart';
import 'studio_controller.dart';
import 'value_slider.dart';

/// Liquify's brushes and settings, and Reconstruct, Reset, Undo, Cancel,
/// Apply.
class LiquifyBar extends StatelessWidget {
  const LiquifyBar({
    super.key,
    required this.controller,
    required this.onApply,
  });
  final StudioController controller;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final c = controller, l = AppLocalizations.of(context);
    final session = c.liquify!;
    final enabled = !c.documentTransition;
    final modes = {
      LiquifyMode.push: (l.liquifyPush, Icons.pan_tool_alt_outlined),
      LiquifyMode.twirlRight: (l.liquifyTwirlRight, Icons.rotate_right),
      LiquifyMode.twirlLeft: (l.liquifyTwirlLeft, Icons.rotate_left),
      LiquifyMode.pinch: (l.liquifyPinch, Icons.compress),
      LiquifyMode.expand: (l.liquifyExpand, Icons.expand),
      LiquifyMode.crystals: (l.liquifyCrystals, Icons.diamond_outlined),
      LiquifyMode.edge: (l.liquifyEdge, Icons.timeline),
      LiquifyMode.reconstruct: (l.liquifyReconstruct, Icons.restore),
    };
    Widget slider(
      String key,
      String label,
      double value,
      ValueChanged<double> onChanged,
    ) => ValueSlider(
      id: 'liquify-$key',
      label: label,
      value: value,
      onChanged: enabled ? onChanged : null,
    );
    return OverlayBar(
      key: const ValueKey('liquify-bar'),
      engaged: c.canvasEngaged,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l.liquify, style: Theme.of(context).textTheme.labelLarge),
                barHint(l.liquifyHint),
                barChoices<LiquifyMode>(
                  keyPrefix: 'liquify-mode',
                  options: modes,
                  selected: session.mode,
                  onSelected: enabled ? (m) => c.setLiquify(mode: m) : null,
                ),
              ],
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  key: const ValueKey('liquify-half'),
                  tooltip: l.liquifyHalfBack,
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled ? c.reconstructLiquify : null,
                  icon: const Icon(Icons.settings_backup_restore, size: 20),
                ),
                IconButton(
                  tooltip: l.adjustReset,
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled ? c.resetLiquify : null,
                  icon: const Icon(Icons.restart_alt, size: 20),
                ),
                IconButton(
                  tooltip: l.undo,
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled && session.canUndo ? c.undoLiquify : null,
                  icon: const Icon(Icons.undo, size: 20),
                ),
                IconButton(
                  tooltip: l.cancel,
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled ? c.cancelLiquify : null,
                  icon: const Icon(Icons.close, size: 20),
                ),
                IconButton.filled(
                  key: const ValueKey('liquify-apply'),
                  tooltip: l.apply,
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled ? onApply : null,
                  icon: const Icon(Icons.check, size: 20),
                ),
              ],
            ),
          ],
        ),
        slider(
          'size',
          l.liquifySize,
          session.size,
          (v) => c.setLiquify(size: v),
        ),
        slider(
          'pressure',
          l.liquifyPressure,
          session.pressure,
          (v) => c.setLiquify(pressure: v),
        ),
        if (session.mode == LiquifyMode.crystals)
          slider(
            'distortion',
            l.liquifyDistortion,
            session.distortion,
            (v) => c.setLiquify(distortion: v),
          ),
        if (session.mode == LiquifyMode.push)
          slider(
            'momentum',
            l.liquifyMomentum,
            session.momentum,
            (v) => c.setLiquify(momentum: v),
          ),
      ],
    );
  }
}
