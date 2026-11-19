import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../drawing/brush_engine.dart';
import '../l10n/app_localizations.dart';
import 'studio_controller.dart';

/// Procreate's Reference window: the canvas (live after each stroke) or a
/// picture, floating over the workspace. Drag its bar to move it, its
/// corner to size it, pinch to look closer; a tap picks a colour.
class ReferenceWindow extends StatefulWidget {
  const ReferenceWindow({
    super.key,
    required this.controller,
    required this.workspace,
    required this.onImport,
  });
  final StudioController controller;

  /// The area it is kept inside.
  final Size workspace;
  final VoidCallback onImport;

  static const minSize = Size(160, 130), bar = 36.0;

  @override
  State<ReferenceWindow> createState() => _ReferenceWindowState();
}

class _ReferenceWindowState extends State<ReferenceWindow> {
  final _view = TransformationController();

  StudioController get c => widget.controller;

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  Rect _kept(Rect r) {
    final w = widget.workspace;
    final double width = r.width.clamp(
      ReferenceWindow.minSize.width,
      math.max(ReferenceWindow.minSize.width, w.width),
    );
    final double height = r.height.clamp(
      ReferenceWindow.minSize.height,
      math.max(ReferenceWindow.minSize.height, w.height),
    );
    return Rect.fromLTWH(
      r.left.clamp(0.0, math.max(0.0, w.width - width)),
      r.top.clamp(0.0, math.max(0.0, w.height - height)),
      width,
      height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final rect = _kept(c.referenceRect);
    final image = c.referenceImage;
    final dimensions = c.document.dimensions;
    final content = image == null
        ? Size(dimensions.width.toDouble(), dimensions.height.toDouble())
        : Size(image.width.toDouble(), image.height.toDouble());
    return Positioned.fromRect(
      rect: rect,
      child: Material(
        key: const ValueKey('reference-window'),
        elevation: 8,
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            GestureDetector(
              key: const ValueKey('reference-bar'),
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => c.placeReference(_kept(rect.shift(d.delta))),
              child: SizedBox(
                height: ReferenceWindow.bar,
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    Icon(
                      Icons.drag_indicator,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        l.reference,
                        style: Theme.of(context).textTheme.labelMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('reference-canvas'),
                      tooltip: l.referenceCanvas,
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      isSelected: image == null,
                      onPressed: c.clearReferenceImage,
                      icon: const Icon(Icons.crop_original),
                    ),
                    IconButton(
                      key: const ValueKey('reference-image'),
                      tooltip: l.referenceImage,
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      isSelected: image != null,
                      onPressed: widget.onImport,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                    ),
                    IconButton(
                      key: const ValueKey('reference-close'),
                      tooltip: l.cancel,
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => c.toggleReference(false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final scale = math.min(
                            box.maxWidth / content.width,
                            box.maxHeight / content.height,
                          );
                          final shown = content * scale;
                          final origin = Offset(
                            (box.maxWidth - shown.width) / 2,
                            (box.maxHeight - shown.height) / 2,
                          );
                          return GestureDetector(
                            key: const ValueKey('reference-view'),
                            onTapUp: (d) {
                              final scene = _view.toScene(d.localPosition);
                              final point = (scene - origin) / scale;
                              if (point.dx < 0 ||
                                  point.dy < 0 ||
                                  point.dx >= content.width ||
                                  point.dy >= content.height) {
                                return;
                              }
                              c.pickFromReference(point);
                            },
                            child: InteractiveViewer(
                              transformationController: _view,
                              maxScale: 12,
                              child: SizedBox(
                                width: box.maxWidth,
                                height: box.maxHeight,
                                child: CustomPaint(
                                  painter: _ReferencePainter(
                                    c,
                                    image,
                                    origin,
                                    scale,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      key: const ValueKey('reference-resize'),
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (d) => c.placeReference(
                        _kept(
                          Rect.fromLTWH(
                            rect.left,
                            rect.top,
                            rect.width + d.delta.dx,
                            rect.height + d.delta.dy,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.open_in_full,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferencePainter extends CustomPainter {
  _ReferencePainter(this.c, this.image, this.origin, this.scale)
    : super(repaint: c);
  final StudioController c;
  final ui.Image? image;
  final Offset origin;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(origin.dx, origin.dy)
      ..scale(scale);
    final picture = image;
    if (picture != null) {
      canvas.drawImage(
        picture,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      paintDocument(
        canvas,
        c.document,
        FreehandBrushEngine(),
        rasterImages: c.rasters.images,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ReferencePainter old) =>
      old.image != image || old.origin != origin || old.scale != scale;
}
