import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../drawing/harmony.dart';
import '../l10n/app_localizations.dart';
import 'value_slider.dart';

enum _View { disc, classic, harmony, sliders }

/// Procreate-style colour picking: a hue ring around a saturation ×
/// brightness square, or HSB and RGB sliders with a hex field, and the
/// colours used most recently. Reports every change while dragging.
class ColorPicker extends StatefulWidget {
  const ColorPicker({
    super.key,
    required this.color,
    required this.onColor,
    required this.recent,
    required this.hexField,
    this.onEyedropper,
  });

  /// ARGB.
  final int color;
  final ValueChanged<int> onColor;
  final List<int> recent;

  /// The hex input, shown with the sliders.
  final Widget hexField;
  final VoidCallback? onEyedropper;

  @override
  State<ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<ColorPicker> {
  var view = _View.disc;
  var harmony = HarmonyMode.complementary;
  late HSVColor hsv = HSVColor.fromColor(Color(widget.color));

  /// The colour this picker last reported, to tell its own updates apart.
  int? _sent;

  @override
  void didUpdateWidget(covariant ColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.color != _sent && widget.color != oldWidget.color) {
      final next = HSVColor.fromColor(Color(widget.color));
      // Grey and black have no hue of their own: keep the one on the ring.
      hsv = next.saturation == 0 || next.value == 0
          ? next.withHue(hsv.hue)
          : next;
    }
  }

  void _set(HSVColor next) {
    setState(() => hsv = next);
    final argb = next.toColor().toARGB32();
    _sent = argb;
    widget.onColor(argb);
  }

  void _setRgb({int? r, int? g, int? b}) {
    final c = hsv.toColor();
    final next = HSVColor.fromColor(
      Color.fromARGB(
        255,
        r ?? (c.r * 255).round(),
        g ?? (c.g * 255).round(),
        b ?? (c.b * 255).round(),
      ),
    );
    _set(next.saturation == 0 ? next.withHue(hsv.hue) : next);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final current = hsv.toColor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              key: const ValueKey('color-current'),
              width: 44,
              height: 28,
              decoration: BoxDecoration(
                color: current,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: scheme.outlineVariant),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SegmentedButton<_View>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(
                    value: _View.disc,
                    tooltip: l.colorDisc,
                    icon: const Icon(Icons.donut_large, size: 18),
                  ),
                  ButtonSegment(
                    value: _View.classic,
                    tooltip: l.colorClassic,
                    icon: const Icon(Icons.crop_square, size: 18),
                  ),
                  ButtonSegment(
                    value: _View.harmony,
                    tooltip: l.colorHarmony,
                    icon: const Icon(Icons.join_inner, size: 18),
                  ),
                  ButtonSegment(
                    value: _View.sliders,
                    tooltip: l.colorValues,
                    icon: const Icon(Icons.tune, size: 18),
                  ),
                ],
                selected: {view},
                onSelectionChanged: (v) => setState(() => view = v.first),
              ),
            ),
            if (widget.onEyedropper != null)
              IconButton(
                tooltip: l.eyedropper,
                onPressed: widget.onEyedropper,
                icon: const Icon(Icons.colorize_outlined),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ...switch (view) {
          _View.disc => [_HueDisc(hsv: hsv, onChanged: _set)],
          _View.classic => [
            _ClassicSquare(hsv: hsv, onChanged: _set),
            const SizedBox(height: 8),
            _GradientSlider(
              id: 'classic-hue',
              full: 360,
              unit: '°',
              label: 'H',
              text: '${hsv.hue.round()}°',
              value: hsv.hue / 360,
              colors: [
                for (var i = 0; i <= 6; i++)
                  HSVColor.fromAHSV(1, i * 60.0 % 360, 1, 1).toColor(),
              ],
              onChanged: (t) => _set(hsv.withHue((t * 360).clamp(0, 359.99))),
            ),
          ],
          _View.harmony => _harmony(l),
          _View.sliders => _values(l, current),
        },
        if (widget.recent.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(l.recentColors, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, color) in widget.recent.indexed)
                Semantics(
                  label:
                      '#${(color & 0xffffff).toRadixString(16).padLeft(6, '0')}',
                  child: InkWell(
                    key: ValueKey('recent-color-$i'),
                    onTap: () {
                      _sent = null;
                      widget.onColor(color);
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Color(color),
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  List<Widget> _harmony(AppLocalizations l) {
    final hues = harmonyHues(harmony, hsv.hue);
    final names = {
      HarmonyMode.complementary: l.harmonyComplementary,
      HarmonyMode.splitComplementary: l.harmonySplit,
      HarmonyMode.analogous: l.harmonyAnalogous,
      HarmonyMode.triadic: l.harmonyTriadic,
      HarmonyMode.tetradic: l.harmonyTetradic,
    };
    return [
      DropdownButton<HarmonyMode>(
        key: const ValueKey('harmony-mode'),
        value: harmony,
        isExpanded: true,
        isDense: true,
        onChanged: (m) => setState(() => harmony = m!),
        items: [
          for (final MapEntry(:key, :value) in names.entries)
            DropdownMenuItem(value: key, child: Text(value)),
        ],
      ),
      const SizedBox(height: 8),
      _HarmonyWheel(hsv: hsv, hues: hues, onChanged: _set),
      const SizedBox(height: 8),
      _GradientSlider(
        id: 'harmony-brightness',
        full: 100,
        unit: '%',
        label: 'B',
        text: '${(hsv.value * 100).round()}%',
        value: hsv.value,
        colors: [
          Colors.black,
          HSVColor.fromAHSV(1, hsv.hue, hsv.saturation, 1).toColor(),
        ],
        onChanged: (t) => _set(hsv.withValue(t)),
      ),
      const SizedBox(height: 8),
      // The harmony's colours: a tap makes one the current colour.
      Row(
        children: [
          for (final (i, hue) in hues.indexed)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: InkWell(
                  key: ValueKey('harmony-swatch-$i'),
                  onTap: () => _set(hsv.withHue(hue)),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 30,
                    decoration: BoxDecoration(
                      color: hsv.withHue(hue).toColor(),
                      borderRadius: BorderRadius.circular(6),
                      border: i == 0
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 2,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ];
  }

  List<Widget> _values(AppLocalizations l, Color current) {
    final h = hsv.hue, s = hsv.saturation, v = hsv.value;
    final r = (current.r * 255).round(),
        g = (current.g * 255).round(),
        b = (current.b * 255).round();
    Color rgb(int r, int g, int b) => Color.fromARGB(255, r, g, b);
    return [
      _GradientSlider(
        id: 'hue',
        full: 360,
        unit: '°',
        label: 'H',
        text: '${h.round()}°',
        value: h / 360,
        colors: [
          for (var i = 0; i <= 6; i++)
            HSVColor.fromAHSV(1, i * 60.0 % 360, 1, 1).toColor(),
        ],
        onChanged: (t) => _set(hsv.withHue((t * 360).clamp(0, 359.99))),
      ),
      _GradientSlider(
        id: 'saturation',
        full: 100,
        unit: '%',
        label: 'S',
        text: '${(s * 100).round()}%',
        value: s,
        colors: [
          HSVColor.fromAHSV(1, h, 0, v).toColor(),
          HSVColor.fromAHSV(1, h, 1, v).toColor(),
        ],
        onChanged: (t) => _set(hsv.withSaturation(t)),
      ),
      _GradientSlider(
        id: 'brightness',
        full: 100,
        unit: '%',
        label: 'B',
        text: '${(v * 100).round()}%',
        value: v,
        colors: [Colors.black, HSVColor.fromAHSV(1, h, s, 1).toColor()],
        onChanged: (t) => _set(hsv.withValue(t)),
      ),
      const SizedBox(height: 6),
      _GradientSlider(
        id: 'red',
        full: 255,
        unit: '',
        label: 'R',
        text: '$r',
        value: r / 255,
        colors: [rgb(0, g, b), rgb(255, g, b)],
        onChanged: (t) => _setRgb(r: (t * 255).round()),
      ),
      _GradientSlider(
        id: 'green',
        full: 255,
        unit: '',
        label: 'G',
        text: '$g',
        value: g / 255,
        colors: [rgb(r, 0, b), rgb(r, 255, b)],
        onChanged: (t) => _setRgb(g: (t * 255).round()),
      ),
      _GradientSlider(
        id: 'blue',
        full: 255,
        unit: '',
        label: 'B',
        text: '$b',
        value: b / 255,
        colors: [rgb(r, g, 0), rgb(r, g, 255)],
        onChanged: (t) => _setRgb(b: (t * 255).round()),
      ),
      const SizedBox(height: 8),
      widget.hexField,
    ];
  }
}

/// A hue ring with a saturation × brightness square inside it.
class _HueDisc extends StatefulWidget {
  const _HueDisc({required this.hsv, required this.onChanged});
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  State<_HueDisc> createState() => _HueDiscState();
}

class _HueDiscState extends State<_HueDisc> {
  /// Which part the finger went down on: the ring or the square.
  bool? _ring;
  Offset? _lastTap;

  static const ringWidth = .14;

  void _at(Offset p, double side, {bool start = false}) {
    final c = Offset(side / 2, side / 2), d = p - c;
    final outer = side / 2, inner = outer * (1 - ringWidth * 2);
    if (start) _ring = d.distance > inner;
    if (_ring ?? false) {
      final hue = (d.direction * 180 / math.pi + 360) % 360;
      widget.onChanged(widget.hsv.withHue(hue));
      return;
    }
    final half = inner / math.sqrt2 * .94;
    final s = ((d.dx + half) / (2 * half)).clamp(0.0, 1.0);
    final v = (1 - (d.dy + half) / (2 * half)).clamp(0.0, 1.0);
    widget.onChanged(widget.hsv.withSaturation(s).withValue(v));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final side = math.min(constraints.maxWidth, 300.0);
      return Center(
        child: GestureDetector(
          key: const ValueKey('color-disc'),
          onPanDown: (d) => _at(d.localPosition, side, start: true),
          onPanUpdate: (d) => _at(d.localPosition, side),
          onPanEnd: (_) => _ring = null,
          // A double tap: the nearest preset colour.
          onDoubleTapDown: (d) => _lastTap = d.localPosition,
          onDoubleTap: () {
            final tap = _lastTap;
            if (tap != null) _at(tap, side, start: true);
            final hsv = widget.hsv;
            final (h, s, v) = snapToPreset(hsv.hue, hsv.saturation, hsv.value);
            widget.onChanged(HSVColor.fromAHSV(1, h, s, v));
          },
          child: CustomPaint(
            size: Size.square(side),
            painter: _DiscPainter(widget.hsv, ringWidth),
          ),
        ),
      );
    },
  );
}

class _DiscPainter extends CustomPainter {
  _DiscPainter(this.hsv, this.ringWidth);
  final HSVColor hsv;
  final double ringWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.width / 2, band = outer * ringWidth;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = band
      ..shader = SweepGradient(
        colors: [
          for (var i = 0; i <= 6; i++)
            HSVColor.fromAHSV(1, i * 60.0 % 360, 1, 1).toColor(),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: outer));
    canvas.drawCircle(c, outer - band / 2, ring);

    final inner = outer - band * 2;
    final half = inner / math.sqrt2 * .94;
    final square = Rect.fromCenter(
      center: c,
      width: half * 2,
      height: half * 2,
    );
    final rounded = RRect.fromRectAndRadius(square, const Radius.circular(6));
    canvas.save();
    canvas.clipRRect(rounded);
    canvas.drawRect(
      square,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()],
        ).createShader(square),
    );
    canvas.drawRect(
      square,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xff000000)],
        ).createShader(square),
    );
    canvas.restore();

    void knob(Offset at, Color fill, double radius) {
      canvas.drawCircle(at, radius, Paint()..color = fill);
      canvas.drawCircle(
        at,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white,
      );
      canvas.drawCircle(
        at,
        radius + 1.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x66000000),
      );
    }

    final angle = hsv.hue * math.pi / 180;
    knob(
      c + Offset(math.cos(angle), math.sin(angle)) * (outer - band / 2),
      HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
      band * .42,
    );
    knob(
      Offset(
        square.left + hsv.saturation * square.width,
        square.top + (1 - hsv.value) * square.height,
      ),
      hsv.toColor(),
      9,
    );
  }

  @override
  bool shouldRepaint(covariant _DiscPainter old) => old.hsv != hsv;
}

/// A labelled bar showing the colours its value moves through.
class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.id,
    required this.full,
    required this.unit,
    required this.label,
    required this.text,
    required this.value,
    required this.colors,
    required this.onChanged,
  });
  final String id, label, text;

  /// Typed as `value × full` with [unit] (degrees, percent, 0–255).
  final double full;
  final String unit;
  final double value;
  final List<Color> colors;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              void at(Offset p) => onChanged((p.dx / width).clamp(0.0, 1.0));
              return GestureDetector(
                key: ValueKey('color-slider-$id'),
                onPanDown: (d) => at(d.localPosition),
                onPanUpdate: (d) => at(d.localPosition),
                child: SizedBox(
                  height: 26,
                  child: CustomPaint(painter: _BarPainter(value, colors)),
                ),
              );
            },
          ),
        ),
        InkWell(
          key: ValueKey('color-slider-$id-value'),
          borderRadius: BorderRadius.circular(6),
          onTap: () async {
            final typed = await askNumber(
              context,
              title: label,
              value: (value * full).roundToDouble(),
              unit: unit,
            );
            if (typed != null) onChanged((typed / full).clamp(0.0, 1.0));
          },
          child: SizedBox(
            width: 44,
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
      ],
    ),
  );
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.value, this.colors);
  final double value;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final bar = Rect.fromLTWH(0, size.height / 2 - 7, size.width, 14);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bar, const Radius.circular(7)),
      Paint()..shader = LinearGradient(colors: colors).createShader(bar),
    );
    final at = Offset(value.clamp(0.0, 1.0) * size.width, size.height / 2);
    canvas.drawCircle(at, 10, Paint()..color = Colors.white);
    canvas.drawCircle(
      at,
      10,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0x55000000),
    );
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.value != value || old.colors != colors;
}

/// Classic: saturation across, brightness down, for the current hue.
class _ClassicSquare extends StatelessWidget {
  const _ClassicSquare({required this.hsv, required this.onChanged});
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final side = math.min(constraints.maxWidth, 300.0);
      void at(Offset p) => onChanged(
        hsv
            .withSaturation((p.dx / side).clamp(0.0, 1.0))
            .withValue((1 - p.dy / side).clamp(0.0, 1.0)),
      );
      return Center(
        child: GestureDetector(
          key: const ValueKey('color-classic'),
          onPanDown: (d) => at(d.localPosition),
          onPanUpdate: (d) => at(d.localPosition),
          child: CustomPaint(
            size: Size.square(side),
            painter: _SquarePainter(hsv),
          ),
        ),
      );
    },
  );
}

class _SquarePainter extends CustomPainter {
  _SquarePainter(this.hsv);
  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)));
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()],
        ).createShader(r),
    );
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xff000000)],
        ).createShader(r),
    );
    canvas.restore();
    final at = Offset(
      hsv.saturation * size.width,
      (1 - hsv.value) * size.height,
    );
    canvas.drawCircle(at, 9, Paint()..color = hsv.toColor());
    canvas.drawCircle(
      at,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_SquarePainter old) => old.hsv != hsv;
}

/// Harmony: a wheel (hue round it, saturation out from the middle) with
/// the harmony's colours marked on it.
class _HarmonyWheel extends StatelessWidget {
  const _HarmonyWheel({
    required this.hsv,
    required this.hues,
    required this.onChanged,
  });
  final HSVColor hsv;
  final List<double> hues;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final side = math.min(constraints.maxWidth, 280.0);
      void at(Offset p) {
        final d = p - Offset(side / 2, side / 2);
        final hue = (d.direction * 180 / math.pi + 360) % 360;
        final saturation = (d.distance / (side / 2)).clamp(0.0, 1.0);
        onChanged(hsv.withHue(hue).withSaturation(saturation));
      }

      return Center(
        child: GestureDetector(
          key: const ValueKey('color-harmony'),
          onPanDown: (d) => at(d.localPosition),
          onPanUpdate: (d) => at(d.localPosition),
          child: CustomPaint(
            size: Size.square(side),
            painter: _WheelPainter(hsv, hues),
          ),
        ),
      );
    },
  );
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.hsv, this.hues);
  final HSVColor hsv;
  final List<double> hues;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: radius);
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..shader = SweepGradient(
          colors: [
            for (var i = 0; i <= 6; i++)
              HSVColor.fromAHSV(1, i * 60.0 % 360, 1, 1).toColor(),
          ],
        ).createShader(rect),
    );
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Colors.white, Color(0x00ffffff)],
        ).createShader(rect),
    );
    canvas.drawCircle(
      c,
      radius,
      Paint()..color = Colors.black.withValues(alpha: 1 - hsv.value),
    );
    for (final (i, hue) in hues.indexed) {
      final angle = hue * math.pi / 180;
      final at =
          c +
          Offset(math.cos(angle), math.sin(angle)) * radius * hsv.saturation;
      final r = i == 0 ? 11.0 : 7.0;
      canvas.drawCircle(at, r, Paint()..color = hsv.withHue(hue).toColor());
      canvas.drawCircle(
        at,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = i == 0 ? 3 : 2
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.hsv != hsv || old.hues != hues;
}
