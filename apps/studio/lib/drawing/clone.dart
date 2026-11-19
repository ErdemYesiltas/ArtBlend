import 'dart:ui';

import '../domain/document.dart';
import 'brush_engine.dart';

/// Clone on one layer: strokes paint the layer's own pixels taken from
/// the source disc's place.
///
/// Aligned (the default) keeps the distance between disc and pen from one
/// stroke to the next, the disc following the pen; locked starts every
/// stroke from where the disc stands.
class CloneSession {
  CloneSession({required this.layerId, required this.source, Offset? disc})
    : disc = disc ?? Offset(source.width / 2, source.height / 2);

  final String layerId;

  /// The layer's own pixels at document size.
  final Image source;

  /// Where the disc stands (document pixels).
  Offset disc;

  bool locked = false;

  /// Disc minus pen while aligned; null until the first stroke (or after
  /// the disc is moved by hand).
  Offset? _aligned;

  /// Disc minus pen for the stroke being drawn.
  Offset? _offset;

  /// Strokes drawn, each with its disc offset; and the one being drawn.
  final List<(InkStroke, Offset)> strokes = [];
  InkStroke? drawing;

  /// The layer with the finished strokes, so a frame draws one image.
  Image? _baked;

  /// Where pixels are taken from right now, while a stroke is drawn.
  Offset? get sampling {
    final stroke = drawing, offset = _offset;
    if (stroke == null || offset == null) return null;
    final last = stroke.points.last;
    return Offset(last.x, last.y) + offset;
  }

  /// Where the disc is shown: following the pen while aligned, still
  /// while locked.
  Offset get shownDisc => locked ? disc : sampling ?? disc;

  void moveDisc(Offset to) {
    disc = _inside(to);
    _aligned = null;
  }

  /// [point] kept on the canvas: a disc beyond its edge could not be seen
  /// (nor would it copy anything).
  Offset _inside(Offset point) => Offset(
    point.dx.clamp(0, source.width.toDouble()),
    point.dy.clamp(0, source.height.toDouble()),
  );

  /// A stroke begins at [start]: its offset is fixed now.
  void begin(InkStroke stroke, Offset start) {
    _offset = locked ? disc - start : _aligned ?? disc - start;
    drawing = stroke;
  }

  void end() {
    final stroke = drawing, offset = _offset;
    drawing = null;
    if (stroke == null || offset == null) return;
    strokes.add((stroke, offset));
    if (!locked) {
      final last = stroke.points.last;
      final followed = Offset(last.x, last.y) + offset;
      disc = _inside(followed);
      // Stopped at the edge: the next stroke aligns afresh from there.
      _aligned = disc == followed ? offset : null;
    }
    _offset = null;
    _bake();
  }

  void undo() {
    if (strokes.isEmpty) return;
    strokes.removeLast();
    _bake();
  }

  void _bake() {
    final recorder = PictureRecorder();
    final bounds = Rect.fromLTWH(
      0,
      0,
      source.width.toDouble(),
      source.height.toDouble(),
    );
    final canvas = Canvas(recorder);
    canvas.drawImage(source, Offset.zero, Paint());
    for (final (stroke, offset) in strokes) {
      _paintStroke(canvas, bounds, stroke, offset);
    }
    final picture = recorder.endRecording();
    final next = picture.toImageSync(source.width, source.height);
    picture.dispose();
    _baked?.dispose();
    _baked = strokes.isEmpty ? null : next;
    if (strokes.isEmpty) next.dispose();
  }

  /// The source pixels [offset] away, laid down where [stroke] covers.
  void _paintStroke(
    Canvas canvas,
    Rect bounds,
    InkStroke stroke,
    Offset offset, {
    bool complete = true,
  }) {
    final outline = FreehandBrushEngine().outline(stroke, complete: complete);
    final area = outline.getBounds().inflate(2).intersect(bounds);
    if (area.isEmpty) return;
    canvas.saveLayer(area, Paint());
    canvas.drawImage(source, -offset, Paint());
    canvas.saveLayer(area, Paint()..blendMode = BlendMode.dstIn);
    canvas.drawPath(
      outline,
      Paint()..color = Color.fromRGBO(255, 255, 255, stroke.opacity),
    );
    canvas.restore();
    canvas.restore();
  }

  /// The layer as it would be.
  void paint(Canvas canvas, Rect bounds) {
    canvas.drawImage(_baked ?? source, Offset.zero, Paint());
    final stroke = drawing, offset = _offset;
    if (stroke != null && offset != null) {
      _paintStroke(canvas, bounds, stroke, offset, complete: false);
    }
  }

  void dispose() {
    _baked?.dispose();
    _baked = null;
    source.dispose();
  }
}
