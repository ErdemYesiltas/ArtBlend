import 'package:material_ui/material_ui.dart';

import '../drawing/adjustments.dart';
import '../l10n/app_localizations.dart';
import 'adjustment_editors.dart';
import 'color_picker.dart';
import 'overlay_bar.dart';
import 'value_slider.dart';
import 'studio_controller.dart';

String adjustmentName(AppLocalizations l, AdjustmentKind kind) =>
    switch (kind) {
      AdjustmentKind.hueSaturationBrightness => l.hueSaturationBrightness,
      AdjustmentKind.colorBalance => l.colorBalance,
      AdjustmentKind.curves => l.curves,
      AdjustmentKind.gradientMap => l.gradientMap,
      AdjustmentKind.gaussianBlur => l.gaussianBlur,
      AdjustmentKind.motionBlur => l.motionBlur,
      AdjustmentKind.perspectiveBlur => l.perspectiveBlur,
      AdjustmentKind.sharpen => l.sharpen,
      AdjustmentKind.noise => l.noise,
      AdjustmentKind.bloom => l.bloom,
      AdjustmentKind.glitch => l.glitch,
      AdjustmentKind.halftone => l.halftone,
      AdjustmentKind.chromaticAberration => l.chromaticAberration,
      AdjustmentKind.recolor => l.recolor,
    };

/// The open adjustment's controls: layer or pencil, its values, and
/// Preview (hold), Undo, Reset, Cancel, Apply.
class AdjustmentBar extends StatefulWidget {
  const AdjustmentBar({
    super.key,
    required this.controller,
    required this.onApply,
  });
  final StudioController controller;
  final VoidCallback onApply;

  @override
  State<AdjustmentBar> createState() => _AdjustmentBarState();
}

class _AdjustmentBarState extends State<AdjustmentBar> {
  ToneRange _range = ToneRange.midtones;
  CurveChannel _channel = CurveChannel.gamma;

  StudioController get c => widget.controller;
  bool get enabled => !c.documentTransition;

  Widget _slider(
    String id,
    String label, {
    double Function(double value)? toNumber,
    double Function(double number)? fromNumber,
    String unit = '%',
  }) => ValueSlider(
    id: 'adjustment-$id',
    label: label,
    value: c.adjustment!.adjustment[id],
    toNumber: toNumber ?? (v) => v * 100,
    fromNumber: fromNumber ?? (n) => n / 100,
    unit: unit,
    labelWidth: 110,
    onChangeStart: enabled ? (_) => c.beginAdjustmentChange() : null,
    onChanged: enabled ? (v) => c.setAdjustmentValue(id, v) : null,
  );

  Widget _degrees(String id, double full) => _slider(
    id,
    AppLocalizations.of(context).adjustAngle,
    toNumber: (v) => v * full,
    fromNumber: (n) => n / full,
    unit: '°',
  );

  /// A choice stored as one of [options]' values in [id].
  Widget _choice(String id, Map<double, String> options) {
    final value = c.adjustment!.adjustment[id];
    final nearest = options.keys.reduce(
      (a, b) => (a - value).abs() <= (b - value).abs() ? a : b,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SegmentedButton<double>(
        key: ValueKey('adjustment-choice-$id'),
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          for (final MapEntry(:key, value: label) in options.entries)
            ButtonSegment(value: key, label: Text(label)),
        ],
        selected: {nearest},
        onSelectionChanged: enabled
            ? (v) {
                c.beginAdjustmentChange();
                c.setAdjustmentValue(id, v.single);
              }
            : null,
      ),
    );
  }

  /// Recolor's new colour: the colour picker over the bar, live.
  Future<void> _pickColor(AppLocalizations l) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.recolorColor),
      content: SizedBox(
        width: 360,
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => ColorPicker(
            color: c.color,
            onColor: c.selectColor,
            recent: c.recentColors,
            hexField: const SizedBox.shrink(),
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.done),
        ),
      ],
    ),
  );

  List<Widget> _controls(AppLocalizations l, AdjustmentSession session) {
    final adjustment = session.adjustment;
    switch (adjustment.kind) {
      case AdjustmentKind.hueSaturationBrightness:
        return [
          _slider('hue', l.adjustHue),
          _slider('saturation', l.adjustSaturation),
          _slider('brightness', l.adjustBrightness),
        ];
      case AdjustmentKind.gaussianBlur:
        return [_slider('amount', l.adjustAmount)];
      case AdjustmentKind.sharpen:
        return [_slider('amount', l.adjustAmount)];
      case AdjustmentKind.noise:
        return [
          _choice('type', {
            0: l.noiseClouds,
            .5: l.noiseBillows,
            1: l.noiseRidges,
          }),
          _slider('amount', l.adjustAmount),
          _slider('scale', l.noiseScale),
          _slider(
            'octaves',
            l.noiseOctaves,
            toNumber: (v) => 1 + (v * 7).roundToDouble(),
            fromNumber: (n) => (n - 1) / 7,
            unit: '',
          ),
          _slider('turbulence', l.noiseTurbulence),
        ];
      case AdjustmentKind.bloom:
        return [
          _slider('amount', l.bloomTransition),
          _slider('size', l.filterSize),
          _slider('burn', l.bloomBurn),
        ];
      case AdjustmentKind.glitch:
        final type = adjustment['type'];
        return [
          _choice('type', {
            0: l.glitchArtifact,
            .375: l.glitchWave,
            .625: l.glitchSignal,
            1: l.glitchDiverge,
          }),
          _slider('amount', l.adjustAmount),
          if (type < .75) _slider('block', l.glitchBlock),
          if (type < .25 || (type > .5 && type < .75))
            _slider('zoom', l.glitchZoom),
        ];
      case AdjustmentKind.halftone:
        return [
          _choice('type', {
            0: l.halftoneFullColor,
            .5: l.halftoneScreenPrint,
            1: l.halftoneNewspaper,
          }),
          _slider('amount', l.filterSize),
        ];
      case AdjustmentKind.chromaticAberration:
        final perspective = adjustment['type'] < .5;
        return [
          _choice('type', {0: l.chromaticPerspective, 1: l.chromaticDisplace}),
          _slider('amount', l.adjustAmount),
          if (perspective)
            _slider('falloff', l.chromaticFalloff)
          else
            _degrees('angle', 360),
        ];
      case AdjustmentKind.motionBlur:
        return [_slider('amount', l.adjustAmount), _degrees('angle', 180)];
      case AdjustmentKind.recolor:
        return [
          Row(
            children: [
              Expanded(
                child: _choice('global', {
                  0: l.recolorFlood,
                  1: l.recolorGlobal,
                }),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: l.recolorColor,
                child: InkWell(
                  key: const ValueKey('recolor-color'),
                  customBorder: const CircleBorder(),
                  onTap: enabled ? () => _pickColor(l) : null,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Color(adjustment.color),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          _slider('threshold', l.recolorThreshold),
        ];
      case AdjustmentKind.perspectiveBlur:
        final directional = adjustment['directional'] > .5;
        return [
          const SizedBox(height: 6),
          SegmentedButton<bool>(
            key: const ValueKey('perspective-mode'),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(value: false, label: Text(l.perspectivePositional)),
              ButtonSegment(value: true, label: Text(l.perspectiveDirectional)),
            ],
            selected: {directional},
            onSelectionChanged: enabled
                ? (v) {
                    c.beginAdjustmentChange();
                    c.setAdjustmentValue('directional', v.single ? 1 : 0);
                  }
                : null,
          ),
          _slider('amount', l.adjustAmount),
          if (directional) _degrees('angle', 360),
        ];
      case AdjustmentKind.colorBalance:
        Widget signed(String id, String label) => _slider(
          id,
          label,
          toNumber: (v) => (v - .5) * 200,
          fromNumber: (n) => n / 200 + .5,
          unit: '',
        );

        return [
          const SizedBox(height: 6),
          SegmentedButton<ToneRange>(
            key: const ValueKey('tone-range'),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(
                value: ToneRange.shadows,
                label: Text(l.toneShadows),
              ),
              ButtonSegment(
                value: ToneRange.midtones,
                label: Text(l.toneMidtones),
              ),
              ButtonSegment(
                value: ToneRange.highlights,
                label: Text(l.toneHighlights),
              ),
            ],
            selected: {_range},
            onSelectionChanged: (v) => setState(() => _range = v.single),
          ),
          signed('${_range.name}Red', l.cyanRed),
          signed('${_range.name}Green', l.magentaGreen),
          signed('${_range.name}Blue', l.yellowBlue),
        ];
      case AdjustmentKind.curves:
        const colors = {
          CurveChannel.gamma: Color(0xff8e8e93),
          CurveChannel.red: Color(0xffe5484d),
          CurveChannel.green: Color(0xff30a46c),
          CurveChannel.blue: Color(0xff3e63dd),
        };
        return [
          const SizedBox(height: 6),
          SegmentedButton<CurveChannel>(
            key: const ValueKey('curve-channel'),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(
                value: CurveChannel.gamma,
                label: Text(l.curveGamma),
              ),
              ButtonSegment(value: CurveChannel.red, label: Text(l.curveRed)),
              ButtonSegment(
                value: CurveChannel.green,
                label: Text(l.curveGreen),
              ),
              ButtonSegment(value: CurveChannel.blue, label: Text(l.curveBlue)),
            ],
            selected: {_channel},
            onSelectionChanged: (v) => setState(() => _channel = v.single),
          ),
          const SizedBox(height: 8),
          Center(
            child: SizedBox(
              width: 210,
              child: CurveEditor(
                points: adjustment.curve(_channel),
                color: colors[_channel]!,
                histogram: session.histogram,
                onChangeStart: c.beginAdjustmentChange,
                onChanged: (points) =>
                    c.setAdjustment(adjustment.withCurve(_channel, points)),
              ),
            ),
          ),
        ];
      case AdjustmentKind.gradientMap:
        final names = {
          GradientPreset.noir: l.gradientNoir,
          GradientPreset.sepia: l.gradientSepia,
          GradientPreset.sunset: l.gradientSunset,
          GradientPreset.ocean: l.gradientOcean,
          GradientPreset.neon: l.gradientNeon,
          GradientPreset.gold: l.gradientGold,
        };
        return [
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final preset in GradientPreset.values)
                ChoiceChip(
                  key: ValueKey('gradient-${preset.name}'),
                  avatar: GradientSwatch(preset.stops),
                  label: Text(names[preset]!),
                  selected: adjustment.gradient == preset.stops,
                  onSelected: enabled
                      ? (_) {
                          c.beginAdjustmentChange();
                          c.setAdjustment(
                            adjustment.withGradient(preset.stops),
                          );
                        }
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 4),
          GradientEditor(
            stops: adjustment.gradient,
            onChangeStart: c.beginAdjustmentChange,
            onChanged: (stops) =>
                c.setAdjustment(c.adjustment!.adjustment.withGradient(stops)),
            onPick: _pickStop,
          ),
          _slider('amount', l.adjustAmount),
        ];
    }
  }

  Future<void> _pickStop(int index) async {
    final l = AppLocalizations.of(context);
    var color = c.adjustment!.adjustment.gradient[index].$2;
    final chosen = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: ColorPicker(
                color: color,
                onColor: (value) => setState(() => color = value),
                recent: c.recentColors,
                hexField: const SizedBox.shrink(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, color),
              child: Text(l.apply),
            ),
          ],
        ),
      ),
    );
    final session = c.adjustment;
    if (chosen == null || session == null) return;
    final stops = [...session.adjustment.gradient];
    if (index >= stops.length) return;
    stops[index] = (stops[index].$1, chosen);
    c.beginAdjustmentChange();
    c.setAdjustment(session.adjustment.withGradient(stops));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final session = c.adjustment!;
    final adjustment = session.adjustment;
    final hint = session.pencil
        ? l.adjustPencilHint
        : switch (adjustment.kind) {
            AdjustmentKind.motionBlur => l.motionHint,
            AdjustmentKind.curves => l.curvesHint,
            AdjustmentKind.gradientMap => l.gradientHint,
            AdjustmentKind.recolor => l.recolorHint,
            _ when adjustment.centred => l.perspectiveHint,
            _ when adjustment.kind.swipe != null => l.adjustSwipeHint,
            _ => null,
          };
    return OverlayBar(
      key: const ValueKey('adjustment-bar'),
      engaged: c.canvasEngaged,
      maxWidth: 600,
      maxHeightFactor: .6,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    adjustmentName(l, adjustment.kind),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                if (hint != null) barHint(hint),
              ],
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                barChoices(
                  keyPrefix: 'adjustment-mode',
                  options: {
                    false: (l.adjustLayer, Icons.layers_outlined),
                    true: (l.adjustPencil, Icons.edit_outlined),
                  },
                  selected: session.pencil,
                  onSelected: enabled ? c.setAdjustmentPencil : null,
                ),
                const SizedBox(width: 4),
                // Held: the layer as it was. A Listener, not a gesture: the
                // button wins the tap and would cancel it.
                Listener(
                  key: const ValueKey('adjustment-preview'),
                  onPointerDown: (_) => c.previewOriginal(true),
                  onPointerUp: (_) => c.previewOriginal(false),
                  onPointerCancel: (_) => c.previewOriginal(false),
                  child: IconButton(
                    tooltip: l.adjustPreview,
                    visualDensity: VisualDensity.compact,
                    onPressed: enabled ? () {} : null,
                    icon: const Icon(Icons.visibility_outlined, size: 20),
                  ),
                ),
                IconButton(
                  tooltip: l.undo,
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled && session.canUndo
                      ? c.undoAdjustment
                      : null,
                  icon: const Icon(Icons.undo, size: 20),
                ),
                IconButton(
                  tooltip: l.adjustReset,
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled ? c.resetAdjustment : null,
                  icon: const Icon(Icons.restart_alt, size: 20),
                ),
                IconButton(
                  tooltip: l.cancel,
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled ? c.cancelAdjustment : null,
                  icon: const Icon(Icons.close, size: 20),
                ),
                IconButton.filled(
                  key: const ValueKey('adjustment-apply'),
                  tooltip: l.apply,
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled ? widget.onApply : null,
                  icon: const Icon(Icons.check, size: 20),
                ),
              ],
            ),
          ],
        ),
        ..._controls(l, session),
      ],
    );
  }
}
