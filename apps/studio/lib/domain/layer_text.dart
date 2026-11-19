import 'dart:ui';

enum TextAlignment { left, center, right, justify }

/// A text layer's words and style (Procreate's Add Text): vector text that
/// stays editable until it is rasterised. Lengths are canvas pixels.
class LayerText {
  const LayerText({
    required this.text,
    required this.origin,
    required this.width,
    this.font = '',
    this.weight = 400,
    this.italic = false,
    this.size = 96,
    this.tracking = 0,
    this.leading = 1.2,
    this.baseline = 0,
    this.alignment = TextAlignment.left,
    this.underline = false,
    this.outline = false,
    this.vertical = false,
    this.uppercase = false,
    this.color = 0xff000000,
  });

  final String text;

  /// The text box's top-left corner.
  final Offset origin;

  /// The box's width: lines wrap at it.
  final double width;

  /// Font family; empty for the platform's default.
  final String font;

  /// 100–900.
  final int weight;
  final bool italic;
  final double size;

  /// Extra space between letters, as a share of [size].
  final double tracking;

  /// Line height, as a multiple of [size].
  final double leading;

  /// Lifts the text off its line, as a share of [size].
  final double baseline;
  final TextAlignment alignment;
  final bool underline;

  /// Letters drawn as outlines only.
  final bool outline;

  /// Letters stacked top to bottom, lines in columns.
  final bool vertical;
  final bool uppercase;
  final int color;

  static const maxLength = 5000;

  /// The text as it is drawn.
  String get shown => uppercase ? text.toUpperCase() : text;

  LayerText copyWith({
    String? text,
    Offset? origin,
    double? width,
    String? font,
    int? weight,
    bool? italic,
    double? size,
    double? tracking,
    double? leading,
    double? baseline,
    TextAlignment? alignment,
    bool? underline,
    bool? outline,
    bool? vertical,
    bool? uppercase,
    int? color,
  }) => LayerText(
    text: text ?? this.text,
    origin: origin ?? this.origin,
    width: (width ?? this.width).clamp(8, 1e5),
    font: font ?? this.font,
    weight: ((weight ?? this.weight) ~/ 100 * 100).clamp(100, 900),
    italic: italic ?? this.italic,
    size: (size ?? this.size).clamp(4, 4000),
    tracking: (tracking ?? this.tracking).clamp(-.5, 2),
    leading: (leading ?? this.leading).clamp(.5, 4),
    baseline: (baseline ?? this.baseline).clamp(-2, 2),
    alignment: alignment ?? this.alignment,
    underline: underline ?? this.underline,
    outline: outline ?? this.outline,
    vertical: vertical ?? this.vertical,
    uppercase: uppercase ?? this.uppercase,
    color: color ?? this.color,
  );

  Map<String, dynamic> toJson() => {
    'text': text,
    'origin': [origin.dx, origin.dy],
    'width': width,
    if (font.isNotEmpty) 'font': font,
    'weight': weight,
    if (italic) 'italic': true,
    'size': size,
    if (tracking != 0) 'tracking': tracking,
    'leading': leading,
    if (baseline != 0) 'baseline': baseline,
    if (alignment != TextAlignment.left) 'alignment': alignment.name,
    if (underline) 'underline': true,
    if (outline) 'outline': true,
    if (vertical) 'vertical': true,
    if (uppercase) 'uppercase': true,
    'color': color,
  };

  factory LayerText.fromJson(Map<String, dynamic> json) {
    final text = json['text'];
    final origin = json['origin'];
    if (text is! String ||
        text.length > maxLength ||
        origin is! List ||
        origin.length != 2) {
      throw const FormatException('Invalid layer text');
    }
    double number(String key, double fallback) {
      final v = (json[key] as num?)?.toDouble() ?? fallback;
      if (!v.isFinite) throw const FormatException('Invalid layer text');
      return v;
    }

    return const LayerText(text: '', origin: Offset.zero, width: 8).copyWith(
      text: text,
      origin: Offset(
        (origin[0] as num).toDouble(),
        (origin[1] as num).toDouble(),
      ),
      width: number('width', 512),
      font: json['font'] as String? ?? '',
      weight: (json['weight'] as num?)?.toInt() ?? 400,
      italic: json['italic'] as bool? ?? false,
      size: number('size', 96),
      tracking: number('tracking', 0),
      leading: number('leading', 1.2),
      baseline: number('baseline', 0),
      alignment:
          TextAlignment.values.asNameMap()[json['alignment']] ??
          TextAlignment.left,
      underline: json['underline'] as bool? ?? false,
      outline: json['outline'] as bool? ?? false,
      vertical: json['vertical'] as bool? ?? false,
      uppercase: json['uppercase'] as bool? ?? false,
      color: (json['color'] as num?)?.toInt() ?? 0xff000000,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LayerText &&
      other.text == text &&
      other.origin == origin &&
      other.width == width &&
      other.font == font &&
      other.weight == weight &&
      other.italic == italic &&
      other.size == size &&
      other.tracking == tracking &&
      other.leading == leading &&
      other.baseline == baseline &&
      other.alignment == alignment &&
      other.underline == underline &&
      other.outline == outline &&
      other.vertical == vertical &&
      other.uppercase == uppercase &&
      other.color == color;

  @override
  int get hashCode => Object.hash(
    text,
    origin,
    width,
    font,
    weight,
    italic,
    size,
    tracking,
    leading,
    baseline,
    alignment,
    underline,
    outline,
    vertical,
    uppercase,
    color,
  );
}
