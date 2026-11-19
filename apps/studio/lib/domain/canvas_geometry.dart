import 'dart:ui';

/// A drawing's size in pixels. Document coordinates are these pixels,
/// independent of window size and device density.
class CanvasSize {
  const CanvasSize(this.width, this.height);
  final int width, height;

  /// Every drawing saved before sizes were stored.
  static const legacy = CanvasSize(1024, 1024);

  static const minSide = 64;

  /// Largest side; the native brush surface and texture limits agree on it.
  static const maxSide = 4096;

  /// Largest canvas whose largest side is [maxSide].
  static const maxBounds = Rect.fromLTWH(0, 0, maxSide + .0, maxSide + .0);

  bool get isValid =>
      width >= minSide &&
      height >= minSide &&
      width <= maxSide &&
      height <= maxSide;

  Rect get rect => Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  Size get size => Size(width.toDouble(), height.toDouble());
  int get pixels => width * height;

  @override
  bool operator ==(Object other) =>
      other is CanvasSize && other.width == width && other.height == height;
  @override
  int get hashCode => Object.hash(width, height);
  @override
  String toString() => '$width × $height';
}
