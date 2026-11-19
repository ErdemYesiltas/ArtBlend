/// How Animation Assist plays.
enum PlaybackMode { loop, pingPong, oneShot }

/// Animation Assist (Procreate's): its settings and each frame's options.
/// Frames are the drawing's top-level layers and groups, bottom first;
/// a frame is known by its layer's or group's id.
class AnimationSettings {
  const AnimationSettings({
    this.enabled = true,
    this.fps = 15,
    this.mode = PlaybackMode.loop,
    this.onionFrames = 2,
    this.onionOpacity = .5,
    this.blendPrimary = false,
    this.onionAhead = 0xff2ec27e,
    this.onionBehind = 0xffe5484d,
    this.holds = const {},
    this.background,
    this.foreground,
  });

  final bool enabled;

  /// 1–60.
  final int fps;
  final PlaybackMode mode;

  /// Frames each side shown faintly (0–12), how strongly (0–1), whether
  /// the frame drawn on is see-through too, and their tints.
  final int onionFrames;
  final double onionOpacity;
  final bool blendPrimary;
  final int onionAhead, onionBehind;

  /// Extra frames a frame stays on screen (0–120), by frame id.
  final Map<String, int> holds;

  /// The first frame kept under every frame, the last kept over them.
  final String? background, foreground;

  static const maxHold = 120, maxOnion = 12;

  int hold(String frame) => holds[frame] ?? 0;

  /// One pass of playback over [frames] (ids, bottom first), one frame
  /// index per tick, a held frame repeated: forward, or for ping-pong
  /// forward and back without repeating the ends. The pinned background
  /// and foreground frames stay under and over the others, not played.
  List<int> playOrder(List<String> frames) {
    final last = frames.length - 1;
    var played = [
      for (var i = 0; i <= last; i++)
        if (!(i == 0 && last > 0 && background == frames[i]) &&
            !(i == last && last > 0 && foreground == frames[i]))
          i,
    ];
    if (played.isEmpty) played = [for (var i = 0; i <= last; i++) i];
    final pass = [
      ...played,
      if (mode == PlaybackMode.pingPong && played.length > 2)
        ...played.reversed.skip(1).take(played.length - 2),
    ];
    return [
      for (final i in pass)
        for (var k = 0; k <= hold(frames[i]); k++) i,
    ];
  }

  AnimationSettings copyWith({
    bool? enabled,
    int? fps,
    PlaybackMode? mode,
    int? onionFrames,
    double? onionOpacity,
    bool? blendPrimary,
    int? onionAhead,
    int? onionBehind,
    Map<String, int>? holds,
    String? background,
    bool clearBackground = false,
    String? foreground,
    bool clearForeground = false,
  }) => AnimationSettings(
    enabled: enabled ?? this.enabled,
    fps: (fps ?? this.fps).clamp(1, 60),
    mode: mode ?? this.mode,
    onionFrames: (onionFrames ?? this.onionFrames).clamp(0, maxOnion),
    onionOpacity: (onionOpacity ?? this.onionOpacity).clamp(0, 1),
    blendPrimary: blendPrimary ?? this.blendPrimary,
    onionAhead: onionAhead ?? this.onionAhead,
    onionBehind: onionBehind ?? this.onionBehind,
    holds: holds ?? this.holds,
    background: clearBackground ? null : background ?? this.background,
    foreground: clearForeground ? null : foreground ?? this.foreground,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'fps': fps,
    'mode': mode.name,
    'onionFrames': onionFrames,
    'onionOpacity': onionOpacity,
    'blendPrimary': blendPrimary,
    'onionAhead': onionAhead,
    'onionBehind': onionBehind,
    if (holds.isNotEmpty) 'holds': holds,
    'background': ?background,
    'foreground': ?foreground,
  };

  /// Anything damaged takes its default.
  factory AnimationSettings.fromJson(Object? json) {
    if (json is! Map) return const AnimationSettings();
    const d = AnimationSettings();
    int number(String key, int fallback) =>
        json[key] is num ? (json[key] as num).round() : fallback;
    final holds = json['holds'];
    return d.copyWith(
      enabled: json['enabled'] as bool? ?? true,
      fps: number('fps', d.fps),
      mode: PlaybackMode.values.asNameMap()[json['mode']] ?? d.mode,
      onionFrames: number('onionFrames', d.onionFrames),
      onionOpacity: json['onionOpacity'] is num
          ? (json['onionOpacity'] as num).toDouble()
          : d.onionOpacity,
      blendPrimary: json['blendPrimary'] as bool? ?? false,
      onionAhead: number('onionAhead', d.onionAhead),
      onionBehind: number('onionBehind', d.onionBehind),
      holds: holds is Map
          ? {
              for (final MapEntry(:key, :value) in holds.entries)
                if (key is String && value is num)
                  key: value.round().clamp(0, maxHold),
            }
          : const {},
      background: json['background'] as String?,
      foreground: json['foreground'] as String?,
    );
  }
}
