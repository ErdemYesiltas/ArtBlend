import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/layer_text.dart';
import '../l10n/app_localizations.dart';
import 'overlay_bar.dart';
import 'studio_controller.dart';
import 'value_slider.dart';

/// Fonts every device of a platform has.
List<String> systemFonts() => switch (defaultTargetPlatform) {
  TargetPlatform.android => const [
    'sans-serif',
    'sans-serif-condensed',
    'serif',
    'monospace',
    'cursive',
    'casual',
  ],
  TargetPlatform.iOS || TargetPlatform.macOS => const [
    'Helvetica Neue',
    'Avenir Next',
    'Futura',
    'Georgia',
    'Times New Roman',
    'Menlo',
    'Snell Roundhand',
    'Marker Felt',
  ],
  _ => const ['sans-serif', 'serif', 'monospace'],
};

/// Add Text: the words, the font and style, rasterise, done.
class TextBar extends StatefulWidget {
  const TextBar({
    super.key,
    required this.controller,
    required this.onImportFont,
    required this.run,
  });
  final StudioController controller;
  final VoidCallback onImportFont;
  final Future<void> Function(Future<void> Function()) run;

  @override
  State<TextBar> createState() => _TextBarState();
}

class _TextBarState extends State<TextBar> {
  /// Selected, so typing replaces it (a new layer's placeholder too).
  late final _field = () {
    final text = widget.controller.editedText?.text ?? '';
    return TextEditingController(text: text)
      ..selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, l = AppLocalizations.of(context);
    final text = c.editedText;
    if (text == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    void set(LayerText Function(LayerText t) change) => c.setText(change);

    Widget toggle(
      String key,
      String tooltip,
      IconData icon,
      bool on,
      LayerText Function(LayerText t, bool on) change,
    ) => IconButton(
      key: ValueKey('text-$key'),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: on ? scheme.primaryContainer : null,
      ),
      onPressed: () => set((t) => change(t, !on)),
      icon: Icon(icon, size: 20),
    );

    final fonts = [...systemFonts(), ...c.importedFonts];
    final id = c.textEditing!;
    return OverlayBar(
      key: const ValueKey('text-bar'),
      engaged: c.canvasEngaged,
      top: true,
      maxWidth: 980,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                key: const ValueKey('text-field'),
                controller: _field,
                autofocus: true,
                minLines: 1,
                maxLines: 3,
                keyboardType: TextInputType.multiline,
                maxLength: LayerText.maxLength,
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  hintText: l.typeText,
                ),
                onChanged: (v) => set((t) => t.copyWith(text: v)),
              ),
            ),
            PopupMenuButton<String>(
              key: const ValueKey('text-font'),
              tooltip:
                  '${l.font}: ${text.font.isEmpty ? l.defaultFont : text.font}',
              icon: const Icon(Icons.font_download_outlined, size: 20),
              onSelected: (font) => font == '\u0000'
                  ? widget.onImportFont()
                  : set((t) => t.copyWith(font: font)),
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                  value: '',
                  checked: text.font.isEmpty,
                  child: Text(l.defaultFont),
                ),
                for (final font in fonts)
                  CheckedPopupMenuItem(
                    value: font,
                    checked: text.font == font,
                    child: Text(font, style: TextStyle(fontFamily: font)),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  key: const ValueKey('text-import-font'),
                  value: '\u0000',
                  child: Text(l.importFont),
                ),
              ],
            ),
            toggle(
              'bold',
              l.bold,
              Icons.format_bold,
              text.weight >= 600,
              (t, on) => t.copyWith(weight: on ? 700 : 400),
            ),
            toggle(
              'italic',
              l.italic,
              Icons.format_italic,
              text.italic,
              (t, on) => t.copyWith(italic: on),
            ),
            toggle(
              'underline',
              l.underline,
              Icons.format_underlined,
              text.underline,
              (t, on) => t.copyWith(underline: on),
            ),
            toggle(
              'outline',
              l.outlineText,
              Icons.format_shapes_outlined,
              text.outline,
              (t, on) => t.copyWith(outline: on),
            ),
            IconButton(
              key: const ValueKey('text-align'),
              tooltip: l.alignment,
              onPressed: () => set(
                (t) => t.copyWith(
                  alignment:
                      TextAlignment.values[(t.alignment.index + 1) %
                          TextAlignment.values.length],
                ),
              ),
              icon: Icon(switch (text.alignment) {
                TextAlignment.left => Icons.format_align_left,
                TextAlignment.center => Icons.format_align_center,
                TextAlignment.right => Icons.format_align_right,
                TextAlignment.justify => Icons.format_align_justify,
              }, size: 20),
            ),
            toggle(
              'caps',
              l.allCaps,
              Icons.text_fields,
              text.uppercase,
              (t, on) => t.copyWith(uppercase: on),
            ),
            toggle(
              'vertical',
              l.verticalText,
              Icons.text_rotate_vertical,
              text.vertical,
              (t, on) => t.copyWith(vertical: on),
            ),
            IconButton(
              key: const ValueKey('text-style'),
              tooltip: l.textStyle,
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _StyleDialog(controller: c),
              ),
              icon: const Icon(Icons.tune, size: 20),
            ),
            IconButton(
              key: const ValueKey('text-rasterize'),
              tooltip: l.rasterize,
              onPressed: () => widget.run(() => c.rasterizeText(id)),
              icon: const Icon(Icons.grid_on, size: 20),
            ),
            barHint(l.textHint),
            IconButton(
              key: const ValueKey('text-done'),
              tooltip: l.done,
              onPressed: c.finishText,
              icon: const Icon(Icons.check, size: 20),
            ),
          ],
        ),
      ],
    );
  }
}

/// Size, weight and spacing, typed or slid.
class _StyleDialog extends StatelessWidget {
  const _StyleDialog({required this.controller});
  final StudioController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.textStyle),
      content: SizedBox(
        width: 380,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final t = controller.editedText;
            if (t == null) return const SizedBox.shrink();
            void set(LayerText next) => controller.setText((_) => next);
            final maxSize = controller.document.dimensions.size.longestSide / 2;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueSlider(
                  id: 'text-size',
                  label: l.textSize,
                  value: t.size,
                  min: 4,
                  max: maxSize.clamp(8, 4000),
                  toNumber: (v) => v,
                  fromNumber: (n) => n,
                  unit: ' px',
                  onChanged: (v) => set(t.copyWith(size: v)),
                ),
                ValueSlider(
                  id: 'text-weight',
                  label: l.fontWeight,
                  value: t.weight.toDouble(),
                  min: 100,
                  max: 900,
                  toNumber: (v) => v,
                  fromNumber: (n) => n,
                  unit: '',
                  onChanged: (v) =>
                      set(t.copyWith(weight: (v / 100).round() * 100)),
                ),
                ValueSlider(
                  id: 'text-tracking',
                  label: l.letterSpacing,
                  value: t.tracking,
                  min: -.5,
                  max: 2,
                  onChanged: (v) => set(t.copyWith(tracking: v)),
                ),
                ValueSlider(
                  id: 'text-leading',
                  label: l.lineSpacing,
                  value: t.leading,
                  min: .5,
                  max: 4,
                  onChanged: (v) => set(t.copyWith(leading: v)),
                ),
                ValueSlider(
                  id: 'text-baseline',
                  label: l.baselineShift,
                  value: t.baseline,
                  min: -2,
                  max: 2,
                  onChanged: (v) => set(t.copyWith(baseline: v)),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.done),
        ),
      ],
    );
  }
}
