import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:artblend_brush_engine/stamp_settings.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/document.dart';
import '../drawing/brush_engine.dart';
import '../drawing/native_stroke.dart';
import '../l10n/app_localizations.dart';
import 'studio_controller.dart';
import 'value_slider.dart';

/// Opens Brush Studio on [brush]; Done saves the edited brush.
Future<void> showBrushStudio(
  BuildContext context,
  StudioController controller,
  BrushPreset brush,
) => showDialog<void>(
  context: context,
  builder: (context) => BrushStudio(controller: controller, preset: brush),
);

enum _Section {
  strokePath,
  taper,
  shape,
  grain,
  dual,
  wetMix,
  rendering,
  pencil,
  properties,
  about,
}

/// Procreate's Brush Studio: the brush's settings by section, and a
/// drawing pad that draws with them as they change.
class BrushStudio extends StatefulWidget {
  const BrushStudio({
    super.key,
    required this.controller,
    required this.preset,
  });
  final StudioController controller;
  final BrushPreset preset;

  @override
  State<BrushStudio> createState() => _BrushStudioState();
}

class _BrushStudioState extends State<BrushStudio> {
  late BrushPreset draft = widget.preset;
  late _Section section = _sections.first;
  late final _name = TextEditingController(text: widget.preset.name);

  /// What was drawn on the pad (pad pixels, pressure), or null for the
  /// sample stroke; and the point being drawn now.
  List<(double, double, double)>? _path;
  List<(double, double, double)> _drawing = [];
  Future<ui.Image>? _preview;
  Timer? _debounce;
  Size _padSize = const Size(400, 160);

  static const tips = [
    'round-soft',
    'round-hard',
    'graphite',
    'chalk',
    'bristle',
    'splatter',
  ];
  static const grains = ['paper', 'rough', 'canvas'];

  List<_Section> get _sections => switch (draft.engine) {
    BrushEngineKind.stamp => const [
      _Section.strokePath,
      _Section.shape,
      _Section.grain,
      _Section.dual,
      _Section.wetMix,
      _Section.rendering,
      _Section.pencil,
      _Section.properties,
      _Section.about,
    ],
    BrushEngineKind.freehand => const [
      _Section.strokePath,
      _Section.taper,
      _Section.properties,
      _Section.about,
    ],
    BrushEngineKind.mypaint => const [_Section.properties, _Section.about],
  };

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    super.dispose();
  }

  void _edit(BrushPreset next) {
    setState(() => draft = next);
    _rerender();
  }

  void _rerender() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || !draft.isNative) return;
      setState(() {
        _preview = renderNativePreview(
          draft,
          width: _padSize.width.round(),
          height: _padSize.height.round(),
          diameter: draft.size,
          path: _path,
        );
      });
    });
  }

  void _stamp(StampSettings next) => _edit(draft.copyWith(stamp: next));

  String _sectionName(AppLocalizations l, _Section s) => switch (s) {
    _Section.strokePath => l.studioStrokePath,
    _Section.taper => l.studioTaper,
    _Section.shape => l.studioShape,
    _Section.grain => l.studioGrain,
    _Section.dual => l.studioDual,
    _Section.wetMix => l.studioWetMix,
    _Section.rendering => l.studioRendering,
    _Section.pencil => l.studioPencil,
    _Section.properties => l.studioProperties,
    _Section.about => l.studioAbout,
  };

  Widget _slider(
    String id,
    String label,
    double value,
    ValueChanged<double> onChanged, {
    double min = 0,
    double max = 1,
    double Function(double)? toNumber,
    double Function(double)? fromNumber,
    String unit = '%',
  }) => ValueSlider(
    id: 'studio-$id',
    label: label,
    value: value,
    min: min,
    max: max,
    labelWidth: 140,
    toNumber: toNumber ?? (v) => v * 100,
    fromNumber: fromNumber ?? (n) => n / 100,
    unit: unit,
    onChanged: onChanged,
  );

  /// Choices of built-in images ([names]), plus what the brush has now
  /// if it is an imported one.
  Widget _images(
    String keyPrefix,
    List<String?> names,
    String? current,
    String Function(String?) label,
    ValueChanged<String?> onSelected,
  ) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final name in names)
        ChoiceChip(
          key: ValueKey('$keyPrefix-${name ?? 'none'}'),
          label: Text(label(name)),
          selected: name == null ? current == null : current == 'builtin:$name',
          onSelected: (_) => onSelected(name == null ? null : 'builtin:$name'),
        ),
      if (current != null && current.startsWith('png:'))
        ChoiceChip(
          label: Text(AppLocalizations.of(context).brushCustomImage),
          selected: true,
          onSelected: (_) {},
        ),
    ],
  );

  String _blendName(AppLocalizations l, DualBlend b) => switch (b) {
    DualBlend.multiply => l.blendMultiply,
    DualBlend.darken => l.blendDarken,
    DualBlend.lighten => l.blendLighten,
    DualBlend.screen => l.blendScreen,
    DualBlend.add => l.blendAdd,
    DualBlend.subtract => l.blendSubtract,
    DualBlend.difference => l.blendDifference,
    DualBlend.overlay => l.blendOverlay,
    DualBlend.colorBurn => l.blendColorBurn,
    DualBlend.colorDodge => l.blendColorDodge,
    DualBlend.linearBurn => l.blendLinearBurn,
    DualBlend.hardMix => l.blendHardMix,
  };

  /// The second tip: a built-in one, or another stamp brush's.
  List<Widget> _dualSettings(AppLocalizations l) {
    final dual = draft.dual;
    void set(DualStamp next) => _edit(draft.copyWith(dual: next));
    final others = [
      for (final b in widget.controller.brushes)
        if (b.isStamp && b.id != draft.id && !b.tip!.startsWith('builtin:')) b,
    ];
    return [
      SwitchListTile(
        key: const ValueKey('studio-dual'),
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(l.dualBrush),
        value: dual != null,
        onChanged: (on) => _edit(
          on
              ? draft.copyWith(
                  dual: const DualStamp(),
                  dualTip: draft.tip == 'builtin:chalk'
                      ? 'builtin:splatter'
                      : 'builtin:chalk',
                )
              : draft.copyWith(clearDual: true),
        ),
      ),
      if (dual != null) ...[
        Text(l.dualTip, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final name in tips)
              ChoiceChip(
                key: ValueKey('studio-dual-tip-$name'),
                label: Text(name),
                selected: draft.dualTip == 'builtin:$name',
                onSelected: (_) =>
                    _edit(draft.copyWith(dualTip: 'builtin:$name')),
              ),
            for (final b in others)
              ChoiceChip(
                key: ValueKey('studio-dual-brush-${b.id}'),
                label: Text(b.name),
                selected: draft.dualTip == b.tip,
                onSelected: (_) => _edit(draft.copyWith(dualTip: b.tip)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<DualBlend>(
          key: ValueKey('studio-dual-blend-${dual.blend.name}'),
          initialValue: dual.blend,
          isExpanded: true,
          decoration: InputDecoration(labelText: l.dualBlend, isDense: true),
          items: [
            for (final b in DualBlend.values)
              DropdownMenuItem(value: b, child: Text(_blendName(l, b))),
          ],
          onChanged: (b) {
            if (b != null) set(dual.copyWith(blend: b));
          },
        ),
        const SizedBox(height: 4),
        _slider(
          'dual-size',
          l.dualSize,
          dual.size,
          (v) => set(dual.copyWith(size: v)),
          min: .05,
          max: 4,
        ),
        _slider(
          'dual-spacing',
          l.brushSpacing,
          dual.spacing,
          (v) => set(dual.copyWith(spacing: v)),
          min: .01,
          max: 4,
        ),
        _slider(
          'dual-scatter',
          l.brushScatter,
          dual.scatter,
          (v) => set(dual.copyWith(scatter: v)),
          max: 4,
        ),
        _slider(
          'dual-size-jitter',
          l.brushSizeJitter,
          dual.sizeJitter,
          (v) => set(dual.copyWith(sizeJitter: v)),
        ),
        _slider(
          'dual-rotation-jitter',
          l.brushRotationJitter,
          dual.rotationJitter,
          (v) => set(dual.copyWith(rotationJitter: v)),
        ),
        SwitchListTile(
          key: const ValueKey('studio-dual-follow'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l.brushFollowStroke),
          value: dual.followStroke,
          onChanged: (v) => set(dual.copyWith(followStroke: v)),
        ),
      ],
      Text(l.dualHint, style: Theme.of(context).textTheme.bodySmall),
    ];
  }

  List<Widget> _settings(AppLocalizations l) {
    final stamp = draft.stamp ?? const StampSettings();
    return switch (section) {
      _Section.strokePath => [
        if (draft.isStamp) ...[
          _slider(
            'spacing',
            l.brushSpacing,
            stamp.spacing,
            (v) => _stamp(stamp.copyWith(spacing: v)),
            min: .01,
            max: 4,
          ),
          _slider(
            'scatter',
            l.brushScatter,
            stamp.scatter,
            (v) => _stamp(stamp.copyWith(scatter: v)),
            max: 4,
          ),
        ] else
          _slider(
            'smoothing',
            l.brushSmoothing,
            draft.smoothing,
            (v) => _edit(draft.copyWith(smoothing: v)),
          ),
      ],
      _Section.taper => [
        _slider(
          'thinning',
          l.brushThinning,
          draft.thinning,
          (v) => _edit(draft.copyWith(thinning: v)),
          min: -1,
        ),
      ],
      _Section.shape => [
        Text(l.brushTip, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        _images(
          'studio-tip',
          tips,
          draft.tip,
          (n) => n ?? '',
          (spec) => _edit(draft.copyWith(tip: spec)),
        ),
        const SizedBox(height: 8),
        _slider(
          'rotation',
          l.brushRotation,
          stamp.rotation,
          (v) => _stamp(stamp.copyWith(rotation: v)),
          min: -360,
          max: 360,
          toNumber: (v) => v,
          fromNumber: (n) => n,
          unit: '°',
        ),
        _slider(
          'rotation-jitter',
          l.brushRotationJitter,
          stamp.rotationJitter,
          (v) => _stamp(stamp.copyWith(rotationJitter: v)),
        ),
        _slider(
          'size-jitter',
          l.brushSizeJitter,
          stamp.sizeJitter,
          (v) => _stamp(stamp.copyWith(sizeJitter: v)),
        ),
        SwitchListTile(
          key: const ValueKey('studio-follow'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l.brushFollowStroke),
          value: stamp.followStroke,
          onChanged: (v) => _stamp(stamp.copyWith(followStroke: v)),
        ),
      ],
      _Section.grain => [
        _images(
          'studio-grain',
          [null, ...grains],
          draft.grain,
          (n) => n ?? l.brushNoGrain,
          (spec) => _edit(
            spec == null
                ? draft.copyWith(clearGrain: true)
                : draft.copyWith(grain: spec),
          ),
        ),
        const SizedBox(height: 8),
        _slider(
          'grain-depth',
          l.brushGrainDepth,
          stamp.grainDepth,
          (v) => _stamp(stamp.copyWith(grainDepth: v)),
        ),
        _slider(
          'grain-scale',
          l.brushGrainScale,
          stamp.grainScale,
          (v) => _stamp(stamp.copyWith(grainScale: v)),
          min: .1,
          max: 8,
        ),
      ],
      _Section.dual => _dualSettings(l),
      _Section.wetMix => [
        _slider(
          'wet-dilution',
          l.wetDilution,
          stamp.dilution,
          (v) => _stamp(stamp.copyWith(dilution: v)),
        ),
        _slider(
          'wet-charge',
          l.wetCharge,
          stamp.charge,
          (v) => _stamp(stamp.copyWith(charge: v)),
          min: .01,
        ),
        _slider(
          'wet-pull',
          l.wetPull,
          stamp.pull,
          (v) => _stamp(stamp.copyWith(pull: v)),
        ),
        Text(l.wetHint, style: Theme.of(context).textTheme.bodySmall),
      ],
      _Section.rendering => [
        _slider(
          'flow',
          l.brushFlow,
          stamp.flow,
          (v) => _stamp(stamp.copyWith(flow: v)),
          min: .01,
        ),
        _slider(
          'opacity-jitter',
          l.brushOpacityJitter,
          stamp.opacityJitter,
          (v) => _stamp(stamp.copyWith(opacityJitter: v)),
        ),
      ],
      _Section.pencil => [
        _slider(
          'pressure-size',
          l.brushPressureSize,
          stamp.pressureSize,
          (v) => _stamp(stamp.copyWith(pressureSize: v)),
        ),
        _slider(
          'pressure-opacity',
          l.brushPressureOpacity,
          stamp.pressureOpacity,
          (v) => _stamp(stamp.copyWith(pressureOpacity: v)),
        ),
      ],
      _Section.properties => [
        TextField(
          key: const ValueKey('studio-name'),
          controller: _name,
          decoration: InputDecoration(labelText: l.brushName),
          onChanged: (v) {
            if (v.trim().isNotEmpty) {
              setState(() => draft = draft.copyWith(name: v.trim()));
            }
          },
        ),
        const SizedBox(height: 8),
        _slider(
          'size',
          l.brushDefaultSize,
          draft.size.clamp(1, 128),
          (v) => _edit(draft.copyWith(size: v)),
          min: 1,
          max: 128,
          toNumber: (v) => v,
          fromNumber: (n) => n,
          unit: ' px',
        ),
      ],
      _Section.about => [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l.brushEngine),
          trailing: Text(switch (draft.engine) {
            BrushEngineKind.stamp => l.stampBrush,
            BrushEngineKind.mypaint => l.mypaintBrush,
            BrushEngineKind.freehand => 'perfect_freehand',
          }),
        ),
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('ID'),
          trailing: SelectableText(draft.id),
        ),
        if (draft.engine == BrushEngineKind.mypaint)
          Text(l.brushMypaintNote, style: const TextStyle(fontSize: 12)),
      ],
    };
  }

  /// The drawing pad: what was drawn there, with the brush as it is.
  Widget _pad(AppLocalizations l) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, 160);
        if (size != _padSize) {
          _padSize = size;
          _preview = null;
          _rerender();
        }
        double pressure(PointerEvent e) {
          final range = e.pressureMax - e.pressureMin;
          return e.kind == PointerDeviceKind.stylus && range > 0
              ? ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0)
              : .6;
        }

        return Tooltip(
          message: l.drawingPad,
          child: Listener(
            key: const ValueKey('studio-pad'),
            onPointerDown: (e) => setState(
              () => _drawing = [
                (e.localPosition.dx, e.localPosition.dy, pressure(e)),
              ],
            ),
            onPointerMove: (e) => setState(
              () => _drawing = [
                ..._drawing,
                (e.localPosition.dx, e.localPosition.dy, pressure(e)),
              ],
            ),
            onPointerUp: (_) {
              if (_drawing.length > 1) _path = _drawing;
              setState(() => _drawing = []);
              _rerender();
            },
            child: Container(
              width: size.width,
              height: size.height,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  if (draft.isNative)
                    FutureBuilder<ui.Image>(
                      future: _preview,
                      builder: (context, snapshot) => snapshot.hasData
                          ? RawImage(
                              image: snapshot.data,
                              color: scheme.onSurface,
                              colorBlendMode: BlendMode.srcIn,
                            )
                          : const SizedBox.shrink(),
                    )
                  else
                    CustomPaint(
                      size: size,
                      painter: _FreehandPad(
                        draft,
                        _path ?? _sample(size),
                        scheme.onSurface,
                      ),
                    ),
                  // The stroke being drawn, until it is drawn properly.
                  CustomPaint(
                    size: size,
                    painter: _Trace(_drawing, scheme.primary),
                  ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: IconButton(
                      tooltip: l.clearPad,
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() => _path = null);
                        _rerender();
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static List<(double, double, double)> _sample(Size size) => [
    for (var i = 0; i <= 80; i++)
      (
        12 + i * (size.width - 24) / 80,
        size.height / 2 + math.sin(i / 10) * size.height * .22,
        .25 + .7 * math.sin(math.pi * i / 80),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = widget.controller;
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final sections = _sections;
    if (!sections.contains(section)) section = sections.first;
    final nav = [
      for (final s in sections)
        narrow
            ? ChoiceChip(
                key: ValueKey('studio-section-${s.name}'),
                label: Text(_sectionName(l, s)),
                selected: s == section,
                onSelected: (_) => setState(() => section = s),
              )
            : ListTile(
                key: ValueKey('studio-section-${s.name}'),
                dense: true,
                selected: s == section,
                title: Text(_sectionName(l, s)),
                onTap: () => setState(() => section = s),
              ),
    ];
    final settings = ListView(
      padding: const EdgeInsets.all(12),
      children: [_pad(l), const SizedBox(height: 12), ..._settings(l)],
    );
    return Dialog(
      key: const ValueKey('brush-studio'),
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 920,
        height: 640,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${l.brushStudio} · ${draft.name}',
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (c.isEdited(draft) ||
                      initialBrushes.any((b) => b.id == draft.id))
                    IconButton(
                      key: const ValueKey('studio-reset'),
                      tooltip: l.brushReset,
                      onPressed: () {
                        final original = initialBrushes
                            .where((b) => b.id == draft.id)
                            .firstOrNull;
                        if (original == null) return;
                        _name.text = original.name;
                        _edit(original);
                      },
                      icon: const Icon(Icons.restart_alt),
                    ),
                  IconButton(
                    tooltip: l.cancel,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                  IconButton.filled(
                    key: const ValueKey('studio-done'),
                    tooltip: l.done,
                    onPressed: () {
                      c.saveBrush(draft);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.check),
                  ),
                ],
              ),
            ),
            const Divider(height: 8),
            Expanded(
              child: narrow
                  ? Column(
                      children: [
                        SizedBox(
                          height: 48,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            children: [
                              for (final chip in nav)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: chip,
                                ),
                            ],
                          ),
                        ),
                        Expanded(child: settings),
                      ],
                    )
                  : Row(
                      children: [
                        SizedBox(width: 180, child: ListView(children: nav)),
                        const VerticalDivider(width: 1),
                        Expanded(child: settings),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A vector (perfect_freehand) brush on the pad.
class _FreehandPad extends CustomPainter {
  _FreehandPad(this.brush, this.path, this.color);
  final BrushPreset brush;
  final List<(double, double, double)> path;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (path.length < 2) return;
    final stroke = InkStroke(
      id: 'pad',
      points: [for (final (x, y, p) in path) InkPoint(x, y, p)],
      color: color.toARGB32(),
      size: math.min(brush.size, 40),
      opacity: 1,
      smoothing: brush.smoothing,
      thinning: brush.thinning,
    );
    canvas.drawPath(
      FreehandBrushEngine().outline(stroke),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_FreehandPad old) =>
      old.brush != brush || old.path != path || old.color != color;
}

/// The pad stroke while it is being drawn.
class _Trace extends CustomPainter {
  _Trace(this.points, this.color);
  final List<(double, double, double)> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = ui.Path()..moveTo(points.first.$1, points.first.$2);
    for (final (x, y, _) in points.skip(1)) {
      path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: .5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_Trace old) => old.points != points;
}
