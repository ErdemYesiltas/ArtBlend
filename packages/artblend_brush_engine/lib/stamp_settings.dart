import 'dart:typed_data';

/// A grayscale image for a stamp brush, one byte per pixel (255 paints):
/// the tip shape stamped along a stroke, or the grain tiled over the canvas.
final class StampImage {
  StampImage(this.pixels, this.width, this.height) {
    if (width < 1 || height < 1 || pixels.length != width * height) {
      throw ArgumentError('Expected width × height pixels.');
    }
  }
  final Uint8List pixels;
  final int width, height;
}

/// How a stamp brush lays its dabs, as Procreate's brush studio describes
/// them. Lengths are fractions of the brush diameter.
final class StampSettings {
  const StampSettings({
    this.spacing = .1,
    this.scatter = 0,
    this.sizeJitter = 0,
    this.opacityJitter = 0,
    this.rotation = 0,
    this.rotationJitter = 0,
    this.followStroke = false,
    this.pressureSize = .6,
    this.pressureOpacity = .3,
    this.flow = 1,
    this.grainDepth = 0,
    this.grainScale = 1,
    this.dilution = 0,
    this.charge = 1,
    this.pull = 0,
  });

  /// Wet mix: water in the paint (0–1), how far a load of paint lasts
  /// (0.01–1, 1 never runs out), and how much colour the brush takes up
  /// from the canvas (0–1). All at their defaults the brush is dry.
  final double dilution, charge, pull;

  bool get wet => dilution > 0 || charge < 1 || pull > 0;

  /// Distance between dabs (0.01–4).
  final double spacing;

  /// Random offset of each dab (0–4).
  final double scatter;

  /// How much smaller a dab may randomly be, and how much fainter (0–1).
  final double sizeJitter, opacityJitter;

  /// Tip angle in degrees (−360–360), and random turn up to ±180° (0–1).
  final double rotation, rotationJitter;

  /// Turns the tip along the stroke's direction.
  final bool followStroke;

  /// How much a light touch shrinks a dab and makes it fainter (0–1).
  final double pressureSize, pressureOpacity;

  /// Each dab's share of the stroke's opacity (0.01–1); overlapping dabs
  /// build up to the stroke opacity and never beyond it.
  final double flow;

  /// How much the grain shows (0–1), and its size on the canvas (0.1–8).
  final double grainDepth, grainScale;

  /// In the order `ab_stamp_load` reads them.
  List<double> get params => [
    spacing,
    scatter,
    sizeJitter,
    opacityJitter,
    rotation,
    rotationJitter,
    followStroke ? 1 : 0,
    pressureSize,
    pressureOpacity,
    flow,
    grainDepth,
    grainScale,
  ];

  @override
  bool operator ==(Object other) {
    if (other is! StampSettings) return false;
    final mine = params, theirs = other.params;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) return false;
    }
    return other.dilution == dilution &&
        other.charge == charge &&
        other.pull == pull;
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(params), dilution, charge, pull);

  StampSettings copyWith({
    double? spacing,
    double? scatter,
    double? sizeJitter,
    double? opacityJitter,
    double? rotation,
    double? rotationJitter,
    bool? followStroke,
    double? pressureSize,
    double? pressureOpacity,
    double? flow,
    double? grainDepth,
    double? grainScale,
    double? dilution,
    double? charge,
    double? pull,
  }) => StampSettings(
    spacing: spacing ?? this.spacing,
    scatter: scatter ?? this.scatter,
    sizeJitter: sizeJitter ?? this.sizeJitter,
    opacityJitter: opacityJitter ?? this.opacityJitter,
    rotation: rotation ?? this.rotation,
    rotationJitter: rotationJitter ?? this.rotationJitter,
    followStroke: followStroke ?? this.followStroke,
    pressureSize: pressureSize ?? this.pressureSize,
    pressureOpacity: pressureOpacity ?? this.pressureOpacity,
    flow: flow ?? this.flow,
    grainDepth: grainDepth ?? this.grainDepth,
    grainScale: grainScale ?? this.grainScale,
    dilution: dilution ?? this.dilution,
    charge: charge ?? this.charge,
    pull: pull ?? this.pull,
  );

  Map<String, Object> toJson() => {
    'spacing': spacing,
    'scatter': scatter,
    'sizeJitter': sizeJitter,
    'opacityJitter': opacityJitter,
    'rotation': rotation,
    'rotationJitter': rotationJitter,
    'followStroke': followStroke,
    'pressureSize': pressureSize,
    'pressureOpacity': pressureOpacity,
    'flow': flow,
    'grainDepth': grainDepth,
    'grainScale': grainScale,
    if (wet) 'dilution': dilution,
    if (wet) 'charge': charge,
    if (wet) 'pull': pull,
  };

  /// Missing values take their defaults; out-of-range ones are refused.
  factory StampSettings.fromJson(Map<String, Object?> json) {
    double read(String key, double fallback, double min, double max) {
      final value = json[key];
      if (value == null) return fallback;
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw FormatException('Invalid stamp setting $key');
      }
      return value.toDouble();
    }

    const d = StampSettings();
    final follow = json['followStroke'];
    if (follow != null && follow is! bool) {
      throw const FormatException('Invalid stamp setting followStroke');
    }
    return StampSettings(
      spacing: read('spacing', d.spacing, .01, 4),
      scatter: read('scatter', d.scatter, 0, 4),
      sizeJitter: read('sizeJitter', d.sizeJitter, 0, 1),
      opacityJitter: read('opacityJitter', d.opacityJitter, 0, 1),
      rotation: read('rotation', d.rotation, -360, 360),
      rotationJitter: read('rotationJitter', d.rotationJitter, 0, 1),
      followStroke: follow as bool? ?? d.followStroke,
      pressureSize: read('pressureSize', d.pressureSize, 0, 1),
      pressureOpacity: read('pressureOpacity', d.pressureOpacity, 0, 1),
      flow: read('flow', d.flow, .01, 1),
      grainDepth: read('grainDepth', d.grainDepth, 0, 1),
      grainScale: read('grainScale', d.grainScale, .1, 8),
      dilution: read('dilution', d.dilution, 0, 1),
      charge: read('charge', d.charge, .01, 1),
      pull: read('pull', d.pull, 0, 1),
    );
  }
}

/// How a dual brush's secondary tip combines with the primary one (on
/// coverage, as blend modes do on colour), in `ab_stamp_dual`'s order.
enum DualBlend {
  multiply,
  darken,
  lighten,
  screen,
  add,
  subtract,
  difference,
  overlay,
  colorBurn,
  colorDodge,
  linearBurn,
  hardMix,
}

/// A dual brush's secondary tip: stamped along the same stroke with its own
/// size (a share of the primary dab), spacing and jitter, then combined.
final class DualStamp {
  const DualStamp({
    this.blend = DualBlend.multiply,
    this.size = 1,
    this.spacing = .2,
    this.scatter = 0,
    this.sizeJitter = 0,
    this.rotationJitter = 0,
    this.followStroke = false,
  });

  final DualBlend blend;

  /// Times the primary dab (0.05–4).
  final double size;

  /// Distance between its dabs, a share of its own diameter (0.01–4), and
  /// random offset (0–4).
  final double spacing, scatter;

  /// 0–1.
  final double sizeJitter, rotationJitter;
  final bool followStroke;

  /// In the order `ab_stamp_dual` reads them.
  List<double> get params => [
    blend.index.toDouble(),
    size,
    spacing,
    scatter,
    sizeJitter,
    rotationJitter,
    followStroke ? 1 : 0,
  ];

  @override
  bool operator ==(Object other) {
    if (other is! DualStamp) return false;
    final mine = params, theirs = other.params;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(params);

  DualStamp copyWith({
    DualBlend? blend,
    double? size,
    double? spacing,
    double? scatter,
    double? sizeJitter,
    double? rotationJitter,
    bool? followStroke,
  }) => DualStamp(
    blend: blend ?? this.blend,
    size: size ?? this.size,
    spacing: spacing ?? this.spacing,
    scatter: scatter ?? this.scatter,
    sizeJitter: sizeJitter ?? this.sizeJitter,
    rotationJitter: rotationJitter ?? this.rotationJitter,
    followStroke: followStroke ?? this.followStroke,
  );

  Map<String, Object> toJson() => {
    'blend': blend.name,
    'size': size,
    'spacing': spacing,
    'scatter': scatter,
    'sizeJitter': sizeJitter,
    'rotationJitter': rotationJitter,
    'followStroke': followStroke,
  };

  /// Missing values take their defaults; anything out of range is refused.
  factory DualStamp.fromJson(Map<String, Object?> json) {
    double read(String key, double fallback, double min, double max) {
      final value = json[key];
      if (value == null) return fallback;
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw FormatException('Invalid dual brush setting $key');
      }
      return value.toDouble();
    }

    const d = DualStamp();
    final blend = json['blend'] == null
        ? d.blend
        : DualBlend.values.asNameMap()[json['blend']] ??
              (throw const FormatException('Invalid dual brush blend'));
    final follow = json['followStroke'];
    if (follow != null && follow is! bool) {
      throw const FormatException('Invalid dual brush setting followStroke');
    }
    return DualStamp(
      blend: blend,
      size: read('size', d.size, .05, 4),
      spacing: read('spacing', d.spacing, .01, 4),
      scatter: read('scatter', d.scatter, 0, 4),
      sizeJitter: read('sizeJitter', d.sizeJitter, 0, 1),
      rotationJitter: read('rotationJitter', d.rotationJitter, 0, 1),
      followStroke: follow as bool? ?? d.followStroke,
    );
  }
}
