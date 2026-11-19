import 'package:material_ui/material_ui.dart';

import '../drawing/guides.dart';
import '../drawing/symmetry.dart';
import '../l10n/app_localizations.dart';
import 'color_picker.dart';
import 'overlay_bar.dart';
import 'studio_controller.dart';
import 'value_slider.dart';

/// Edit Drawing Guide: the guide's kind, symmetry, and look.
class GuideBar extends StatelessWidget {
  const GuideBar({super.key, required this.controller});
  final StudioController controller;

  Future<void> _pickColor(BuildContext context) async {
    final c = controller, l = AppLocalizations.of(context);
    var color = c.guide.color;
    final chosen = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l.guideColor),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: ColorPicker(
                color: color,
                onColor: (value) => setState(() => color = value),
                recent: c.recentColors,
                hexField: const SizedBox.shrink(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, color),
              child: Text(l.apply),
            ),
          ],
        ),
      ),
    );
    if (chosen != null) c.setGuide(c.guide.copyWith(color: chosen));
  }

  @override
  Widget build(BuildContext context) {
    final c = controller, l = AppLocalizations.of(context);
    final guide = c.guide;
    return OverlayBar(
      key: const ValueKey('guide-bar'),
      engaged: c.canvasEngaged,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                barChoices<GuideKind>(
                  keyPrefix: 'guide-kind',
                  options: {
                    GuideKind.none: (l.guideNone, Icons.block),
                    GuideKind.grid: (l.guideGrid, Icons.grid_4x4),
                    GuideKind.isometric: (
                      l.guideIsometric,
                      Icons.change_history,
                    ),
                    GuideKind.perspective: (
                      l.guidePerspective,
                      Icons.view_in_ar_outlined,
                    ),
                  },
                  selected: guide.kind,
                  onSelected: (kind) => c.setGuide(guide.copyWith(kind: kind)),
                ),
                barHint(l.guideHint),
                if (guide.kind == GuideKind.perspective &&
                    guide.vanishing.length > 1)
                  IconButton(
                    key: const ValueKey('guide-remove-point'),
                    tooltip: l.guideRemovePoint,
                    onPressed: () => c.setGuide(
                      guide.copyWith(
                        vanishing: guide.vanishing.sublist(
                          0,
                          guide.vanishing.length - 1,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                  ),
              ],
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                barChoices<SymmetryKind>(
                  keyPrefix: 'guide-symmetry',
                  options: {
                    SymmetryKind.off: (l.symmetryOff, Icons.do_not_disturb_alt),
                    SymmetryKind.vertical: (
                      l.symmetryVertical,
                      Icons.border_vertical,
                    ),
                    SymmetryKind.horizontal: (
                      l.symmetryHorizontal,
                      Icons.border_horizontal,
                    ),
                    SymmetryKind.quadrant: (
                      l.symmetryQuadrant,
                      Icons.grid_view,
                    ),
                    SymmetryKind.radial: (
                      l.symmetryRadial,
                      Icons.filter_tilt_shift,
                    ),
                  },
                  selected: c.symmetry,
                  onSelected: c.setSymmetry,
                ),
                IconButton(
                  key: const ValueKey('guide-rotational'),
                  tooltip: l.guideRotational,
                  isSelected: guide.rotational,
                  onPressed: () =>
                      c.setGuide(guide.copyWith(rotational: !guide.rotational)),
                  icon: const Icon(Icons.rotate_right, size: 20),
                ),
                IconButton(
                  key: const ValueKey('guide-color'),
                  tooltip: l.guideColor,
                  onPressed: () => _pickColor(context),
                  icon: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Color(guide.color),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
                IconButton.filled(
                  key: const ValueKey('guide-done'),
                  tooltip: l.done,
                  onPressed: () => c.setGuideEditing(false),
                  icon: const Icon(Icons.check, size: 20),
                ),
              ],
            ),
          ],
        ),
        if (guide.kind != GuideKind.none)
          ValueSlider(
            id: 'guide-grid-size',
            label: l.gridGuide,
            value: guide.gridSize,
            min: 8,
            max: 512,
            toNumber: (v) => v,
            fromNumber: (n) => n,
            unit: ' px',
            onChanged: (v) => c.setGuide(guide.copyWith(gridSize: v)),
          ),
        ValueSlider(
          id: 'guide-opacity',
          label: l.opacity,
          value: guide.opacity,
          min: .05,
          onChanged: (v) => c.setGuide(guide.copyWith(opacity: v)),
        ),
        ValueSlider(
          id: 'guide-thickness',
          label: l.guideThickness,
          value: guide.thickness,
          min: .5,
          max: 6,
          toNumber: (v) => v,
          fromNumber: (n) => n,
          unit: ' px',
          onChanged: (v) => c.setGuide(guide.copyWith(thickness: v)),
        ),
      ],
    );
  }
}
