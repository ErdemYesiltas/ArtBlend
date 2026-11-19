import 'canvas_geometry.dart';

enum CanvasUnit {
  px('px', 1),
  mm('mm', 1 / 25.4),
  cm('cm', 1 / 2.54),
  inch('in', 1);

  const CanvasUnit(this.symbol, this.inches);
  final String symbol;

  /// One unit in inches (pixels need the DPI: see [toPixels]).
  final double inches;

  double toPixels(double value, int dpi) =>
      this == px ? value : value * inches * dpi;

  double fromPixels(double pixels, int dpi) =>
      this == px ? pixels : pixels / (inches * dpi);
}

/// A canvas size to start a drawing from: in pixels, or in a print unit at
/// a resolution.
class CanvasPreset {
  const CanvasPreset({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    this.unit = CanvasUnit.px,
    this.dpi = 132,
  });

  final String id, name;

  /// In [unit].
  final double width, height;
  final CanvasUnit unit;
  final int dpi;

  static const minDpi = 36, maxDpi = 1200;

  CanvasSize get size => CanvasSize(
    unit.toPixels(width, dpi).round(),
    unit.toPixels(height, dpi).round(),
  );

  CanvasPreset copyWith({
    String? name,
    double? width,
    double? height,
    CanvasUnit? unit,
    int? dpi,
  }) => CanvasPreset(
    id: id,
    name: name ?? this.name,
    width: width ?? this.width,
    height: height ?? this.height,
    unit: unit ?? this.unit,
    dpi: (dpi ?? this.dpi).clamp(minDpi, maxDpi),
  );

  /// The same pixels in [next] units.
  CanvasPreset inUnit(CanvasUnit next) {
    final px = size;
    double round(double v) => (v * 100).roundToDouble() / 100;
    return copyWith(
      unit: next,
      width: round(next.fromPixels(px.width.toDouble(), dpi)),
      height: round(next.fromPixels(px.height.toDouble(), dpi)),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'width': width,
    'height': height,
    'unit': unit.name,
    'dpi': dpi,
  };

  /// Null for anything damaged.
  static CanvasPreset? fromJson(Object? json) {
    if (json is! Map) return null;
    final width = json['width'], height = json['height'];
    final unit = CanvasUnit.values.asNameMap()[json['unit']];
    if (json['id'] is! String ||
        json['name'] is! String ||
        width is! num ||
        height is! num ||
        unit == null ||
        json['dpi'] is! int) {
      return null;
    }
    final preset = CanvasPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      width: width.toDouble(),
      height: height.toDouble(),
      unit: unit,
      dpi: (json['dpi'] as int).clamp(minDpi, maxDpi),
    );
    return preset.width.isFinite && preset.height.isFinite ? preset : null;
  }

  /// Procreate's starting sizes (names are given by the editor).
  static const builtIn = [
    CanvasPreset(id: 'square', name: 'square', width: 2048, height: 2048),
    CanvasPreset(id: '4k', name: '4k', width: 3840, height: 2160),
    CanvasPreset(
      id: 'a4',
      name: 'a4',
      width: 210,
      height: 297,
      unit: CanvasUnit.mm,
      dpi: 300,
    ),
    CanvasPreset(
      id: 'photo',
      name: 'photo',
      width: 6,
      height: 4,
      unit: CanvasUnit.inch,
      dpi: 300,
    ),
    CanvasPreset(
      id: 'letter',
      name: 'letter',
      width: 8.5,
      height: 11,
      unit: CanvasUnit.inch,
      dpi: 300,
    ),
  ];
}
