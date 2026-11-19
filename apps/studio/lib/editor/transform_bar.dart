import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../drawing/layer_transform.dart';
import '../l10n/app_localizations.dart';
import 'overlay_bar.dart';
import 'studio_controller.dart';
import 'value_slider.dart';

class TransformBar extends StatelessWidget {
  const TransformBar({
    super.key,
    required this.controller,
    required this.onApply,
  });
  final StudioController controller;
  final VoidCallback onApply;

  /// Snapping's distance and velocity.
  Future<void> _snapSettings(BuildContext context) {
    final c = controller, l = AppLocalizations.of(context);
    return showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l.snapSettings),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueSlider(
                  id: 'snap-distance',
                  label: l.snapDistance,
                  value: c.snapDistance,
                  min: 4,
                  max: 60,
                  toNumber: (v) => v,
                  fromNumber: (n) => n,
                  unit: ' px',
                  onChanged: (v) =>
                      setState(() => c.setSnapSettings(distance: v)),
                ),
                ValueSlider(
                  id: 'snap-velocity',
                  label: l.snapVelocity,
                  value: c.snapVelocity,
                  min: 100,
                  max: 5000,
                  toNumber: (v) => v,
                  fromNumber: (n) => n,
                  unit: ' px/s',
                  onChanged: (v) =>
                      setState(() => c.setSnapSettings(velocity: v)),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.done),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = controller, l = AppLocalizations.of(context);
    final draft = c.transformDraft!;
    final enabled = !c.documentTransition;
    void preview(LayerTransform Function(LayerTransform) change) {
      final current = c.transformDraft;
      if (current != null) c.previewTransform(change(current));
    }

    final hint = [
      switch (c.transformMode) {
        TransformMode.uniform => l.transformHint,
        TransformMode.freeform => l.transformFreeformHint,
        TransformMode.distort => l.transformDistortHint,
        TransformMode.warp => l.transformWarpHint,
      },
      if (c.document.activeLayer.mask != null) l.transformMaskHint,
    ].join('\n\n');
    IconButton icon(
      String tooltip,
      IconData data,
      LayerTransform Function(LayerTransform) change, {
      required String key,
    }) => IconButton(
      key: ValueKey(key),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: enabled ? () => preview(change) : null,
      icon: Icon(data, size: 20),
    );
    return OverlayBar(
      key: const ValueKey('transform-bar'),
      engaged: c.canvasEngaged,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                barChoices(
                  keyPrefix: 'transform-mode',
                  options: {
                    TransformMode.freeform: (
                      l.transformFreeform,
                      Icons.open_in_full,
                    ),
                    TransformMode.uniform: (
                      l.transformUniform,
                      Icons.aspect_ratio,
                    ),
                    TransformMode.distort: (
                      l.transformDistort,
                      Icons.crop_rotate,
                    ),
                    TransformMode.warp: (l.transformWarp, Icons.grid_on),
                  },
                  selected: c.transformMode,
                  onSelected: enabled ? c.setTransformMode : null,
                ),
                barHint(hint),
              ],
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  key: const ValueKey('transform-snapping'),
                  tooltip: l.snapping,
                  isSelected: c.transformSnapping,
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled
                      ? () => c.setTransformSnapping(!c.transformSnapping)
                      : null,
                  icon: const Icon(Icons.vertical_align_center, size: 20),
                ),
                if (c.transformSnapping)
                  IconButton(
                    key: const ValueKey('transform-snap-settings'),
                    tooltip: l.snapSettings,
                    visualDensity: VisualDensity.compact,
                    onPressed: enabled ? () => _snapSettings(context) : null,
                    icon: const Icon(Icons.tune, size: 20),
                  ),
                IconButton(
                  key: const ValueKey('transform-magnetics'),
                  tooltip: l.magnetics,
                  isSelected: c.transformMagnetics,
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled
                      ? () => c.setTransformMagnetics(!c.transformMagnetics)
                      : null,
                  icon: const Icon(Icons.straighten, size: 20),
                ),
                icon(
                  l.flipHorizontal,
                  Icons.flip,
                  (d) => d.flipped(horizontal: true),
                  key: 'transform-flip-h',
                ),
                IconButton(
                  key: const ValueKey('transform-flip-v'),
                  tooltip: l.flipVertical,
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled
                      ? () => preview((d) => d.flipped(horizontal: false))
                      : null,
                  icon: Transform.rotate(
                    angle: math.pi / 2,
                    child: const Icon(Icons.flip, size: 20),
                  ),
                ),
                icon(
                  l.rotate45,
                  Icons.rotate_right,
                  (d) => d.rotatedBy(math.pi / 4),
                  key: 'transform-rotate-45',
                ),
                icon(
                  l.fitToScreen,
                  Icons.fit_screen_outlined,
                  (d) => d.fittedTo(c.document.dimensions.rect),
                  key: 'transform-fit',
                ),
                PopupMenuButton<FilterQuality>(
                  key: const ValueKey('transform-filter'),
                  tooltip: l.interpolation,
                  enabled: enabled,
                  initialValue: draft.filter == FilterQuality.medium
                      ? FilterQuality.low
                      : draft.filter,
                  onSelected: c.setTransformFilter,
                  icon: const Icon(Icons.blur_linear, size: 20),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: FilterQuality.none,
                      child: Text(l.interpolationNearest),
                    ),
                    PopupMenuItem(
                      value: FilterQuality.low,
                      child: Text(l.interpolationBilinear),
                    ),
                    PopupMenuItem(
                      value: FilterQuality.high,
                      child: Text(l.interpolationBicubic),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: l.resetTransform,
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled ? c.resetTransform : null,
                  icon: const Icon(Icons.restart_alt, size: 20),
                ),
                IconButton(
                  tooltip: l.cancel,
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled ? c.cancelTransform : null,
                  icon: const Icon(Icons.close, size: 20),
                ),
                IconButton.filled(
                  key: const ValueKey('transform-apply'),
                  tooltip: l.apply,
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled ? onApply : null,
                  icon: const Icon(Icons.check, size: 20),
                ),
              ],
            ),
          ],
        ),
        // Distort and Warp too: a mesh is resized and turned as a whole.
        ValueSlider(
          id: 'transform-scale',
          label: l.scale,
          labelWidth: 64,
          value: math.log(draft.shownScale.clamp(.05, 8)),
          min: math.log(.05),
          max: math.log(8),
          toNumber: (v) => math.exp(v) * 100,
          fromNumber: (n) => math.log(math.max(n, 5) / 100),
          onChanged: enabled
              ? (v) => preview((d) => d.withShownScale(math.exp(v)))
              : null,
        ),
        ValueSlider(
          id: 'transform-rotation',
          label: l.rotation,
          labelWidth: 64,
          value: draft.shownRotation,
          min: -math.pi,
          max: math.pi,
          toNumber: (v) => v * 180 / math.pi,
          fromNumber: (n) => n * math.pi / 180,
          unit: '°',
          onChanged: enabled
              ? (v) => preview((d) => d.withShownRotation(v))
              : null,
        ),
      ],
    );
  }
}
