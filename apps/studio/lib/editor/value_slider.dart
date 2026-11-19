import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';

/// Asks for a number in place of a slider (a pen is too fine to hit an
/// exact value): [value] shown to start with, null when cancelled.
Future<double?> askNumber(
  BuildContext context, {
  required String title,
  required double value,
  String unit = '',
}) => showDialog<double>(
  context: context,
  builder: (context) => _NumberDialog(title: title, value: value, unit: unit),
);

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({
    required this.title,
    required this.value,
    required this.unit,
  });
  final String title, unit;
  final double value;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final _field = () {
    final v = widget.value;
    final text = v == v.roundToDouble()
        ? v.round().toString()
        : v.toStringAsFixed(1);
    // Selected, so typing replaces it.
    return TextEditingController(text: text)
      ..selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _done() =>
      Navigator.pop(context, double.tryParse(_field.text.replaceAll(',', '.')));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('number-field'),
        controller: _field,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(
          signed: true,
          decimal: true,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
        ],
        decoration: InputDecoration(
          hintText: l.enterValue,
          suffixText: widget.unit.isEmpty ? null : widget.unit,
        ),
        onSubmitted: (_) => _done(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _done, child: Text(l.apply)),
      ],
    );
  }
}

/// A slider with its name and its value; tapping the value types one.
/// The value is shown and typed as [toNumber] of it (a percentage of 0–1
/// by default) followed by [unit].
class ValueSlider extends StatelessWidget {
  const ValueSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.toNumber = _percent,
    this.fromNumber = _fromPercent,
    this.unit = '%',
    this.icon,
    this.onChangeStart,
    this.onChangeEnd,
    this.id,
    this.labelWidth = 92,
  });

  static double _percent(double v) => v * 100;
  static double _fromPercent(double n) => n / 100;

  final String label;
  final double value, min, max;
  final ValueChanged<double>? onChanged;
  final double Function(double value) toNumber, fromNumber;
  final String unit;

  /// In place of [label]: an icon, the name in its tooltip.
  final IconData? icon;
  final ValueChanged<double>? onChangeStart, onChangeEnd;

  /// Keys the slider (`id`) and its value (`id-value`).
  final String? id;
  final double labelWidth;

  String _shown(double v) => '${toNumber(v).round()}$unit';

  Future<void> _type(BuildContext context) async {
    final typed = await askNumber(
      context,
      title: label,
      value: toNumber(value),
      unit: unit,
    );
    if (typed == null || onChanged == null) return;
    final next = fromNumber(typed).clamp(min, max);
    onChangeStart?.call(value);
    onChanged!(next);
    onChangeEnd?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Row(
      children: [
        if (icon != null)
          Tooltip(message: label, child: Icon(icon, size: 18))
        else
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Expanded(
          child: Slider(
            key: id == null ? null : ValueKey<String>(id!),
            value: value.clamp(min, max),
            min: min,
            max: max,
            semanticFormatterCallback: (v) => '$label ${_shown(v)}',
            onChangeStart: onChangeStart,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        Tooltip(
          message: label,
          child: InkWell(
            key: id == null ? null : ValueKey('$id-value'),
            borderRadius: BorderRadius.circular(6),
            onTap: onChanged == null ? null : () => _type(context),
            child: Container(
              constraints: const BoxConstraints(minWidth: 48),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _shown(value),
                style: style,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
