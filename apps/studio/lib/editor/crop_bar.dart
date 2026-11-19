import 'package:material_ui/material_ui.dart';

import '../domain/document.dart';
import '../l10n/app_localizations.dart';
import 'overlay_bar.dart';
import 'studio_controller.dart';
import 'value_slider.dart';

/// Crop & Resize: size (typed), resample, DPI, turn and flip the canvas,
/// cancel, apply.
class CropBar extends StatelessWidget {
  const CropBar({super.key, required this.controller, required this.run});
  final StudioController controller;

  /// Runs an action and reports its failure, as the editor does.
  final Future<void> Function(Future<void> Function()) run;

  @override
  Widget build(BuildContext context) {
    final c = controller, l = AppLocalizations.of(context);
    final crop = c.canvasCrop!;
    final enabled = !c.documentTransition;
    final width = crop.resample ? crop.target.width : crop.rect.width.round();
    final height = crop.resample
        ? crop.target.height
        : crop.rect.height.round();

    Future<void> typeSide({required bool horizontal}) async {
      final typed = await askNumber(
        context,
        title: horizontal ? l.canvasWidth : l.canvasHeight,
        value: (horizontal ? width : height).toDouble(),
        unit: ' px',
      );
      if (typed == null) return;
      final side = typed.round().clamp(CanvasSize.minSide, CanvasSize.maxSide);
      if (crop.resample) {
        c.setCanvasCrop(
          target: horizontal
              ? CanvasSize(side, crop.target.height)
              : CanvasSize(crop.target.width, side),
        );
      } else {
        // Typed: the crop grows or shrinks around its middle.
        final r = crop.rect;
        c.setCanvasCrop(
          rect: Rect.fromCenter(
            center: r.center,
            width: horizontal ? side.toDouble() : r.width,
            height: horizontal ? r.height : side.toDouble(),
          ),
        );
      }
    }

    Widget chip(String key, String text, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        key: ValueKey(key),
        borderRadius: BorderRadius.circular(6),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(text, style: Theme.of(context).textTheme.labelSmall),
        ),
      ),
    );

    return OverlayBar(
      key: const ValueKey('crop-bar'),
      engaged: c.canvasEngaged,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l.cropResize,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                barHint(l.cropHint),
                Tooltip(
                  message: l.canvasWidth,
                  child: chip(
                    'crop-width',
                    '$width px',
                    () => typeSide(horizontal: true),
                  ),
                ),
                const Text('×'),
                Tooltip(
                  message: l.canvasHeight,
                  child: chip(
                    'crop-height',
                    '$height px',
                    () => typeSide(horizontal: false),
                  ),
                ),
                Tooltip(
                  message: 'DPI',
                  child: chip('crop-dpi', '${c.document.dpi} DPI', () async {
                    final typed = await askNumber(
                      context,
                      title: 'DPI',
                      value: c.document.dpi.toDouble(),
                    );
                    if (typed != null) c.setDpi(typed.round());
                  }),
                ),
                IconButton(
                  key: const ValueKey('crop-resample'),
                  tooltip: l.cropResample,
                  isSelected: crop.resample,
                  onPressed: enabled
                      ? () => c.setCanvasCrop(
                          resample: !crop.resample,
                          rect: c.document.dimensions.rect,
                          target: c.document.dimensions,
                        )
                      : null,
                  icon: const Icon(Icons.photo_size_select_large, size: 20),
                ),
              ],
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  key: const ValueKey('canvas-rotate-left'),
                  tooltip: l.rotateCanvasLeft,
                  onPressed: enabled
                      ? () => run(
                          () => c.reshapeFromCrop(
                            () => c.rotateCanvas(clockwise: false),
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.rotate_90_degrees_ccw, size: 20),
                ),
                IconButton(
                  key: const ValueKey('canvas-rotate-right'),
                  tooltip: l.rotateCanvasRight,
                  onPressed: enabled
                      ? () => run(
                          () => c.reshapeFromCrop(
                            () => c.rotateCanvas(clockwise: true),
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.rotate_90_degrees_cw, size: 20),
                ),
                IconButton(
                  key: const ValueKey('canvas-flip-h'),
                  tooltip: l.flipCanvasHorizontal,
                  onPressed: enabled
                      ? () => run(
                          () => c.reshapeFromCrop(
                            () => c.flipCanvas(horizontal: true),
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.flip, size: 20),
                ),
                IconButton(
                  key: const ValueKey('canvas-flip-v'),
                  tooltip: l.flipCanvasVertical,
                  onPressed: enabled
                      ? () => run(
                          () => c.reshapeFromCrop(
                            () => c.flipCanvas(horizontal: false),
                          ),
                        )
                      : null,
                  icon: const RotatedBox(
                    quarterTurns: 1,
                    child: Icon(Icons.flip, size: 20),
                  ),
                ),
                IconButton(
                  tooltip: l.resetTransform,
                  onPressed: enabled
                      ? () => c.setCanvasCrop(
                          rect: c.document.dimensions.rect,
                          target: c.document.dimensions,
                        )
                      : null,
                  icon: const Icon(Icons.restart_alt, size: 20),
                ),
                IconButton(
                  tooltip: l.cancel,
                  onPressed: enabled ? c.cancelCanvasCrop : null,
                  icon: const Icon(Icons.close, size: 20),
                ),
                IconButton.filled(
                  key: const ValueKey('crop-apply'),
                  tooltip: l.apply,
                  onPressed: enabled ? () => run(c.applyCanvasCrop) : null,
                  icon: const Icon(Icons.check, size: 20),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
