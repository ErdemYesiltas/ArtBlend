import 'package:material_ui/material_ui.dart';

import '../domain/layer_text.dart';
import '../editor/color_picker.dart';
import '../editor/text_bar.dart' show systemFonts;
import '../editor/value_slider.dart';
import '../l10n/app_localizations.dart';
import 'movie_controller.dart';

/// Text content [id]'s words and style in a dialog; saved as one undo
/// step.
Future<void> editTextContent(
  BuildContext context,
  MovieController c,
  String id,
) async {
  final text = c.textOf(id);
  if (text == null) return;
  final next = await showDialog<LayerText>(
    context: context,
    builder: (_) => TextContentDialog(text: text),
  );
  if (next != null) c.setText(id, next);
}

/// A text content's words, font, size, weight, slant, colour and
/// alignment. Pops the text as set, or null.
class TextContentDialog extends StatefulWidget {
  const TextContentDialog({
    super.key,
    required this.text,
    this.recent = const [],
  });
  final LayerText text;
  final List<int> recent;

  @override
  State<TextContentDialog> createState() => _TextContentDialogState();
}

class _TextContentDialogState extends State<TextContentDialog> {
  late final words = TextEditingController(text: widget.text.text);
  late LayerText text = widget.text;
  bool picking = false;

  @override
  void dispose() {
    words.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final fonts = {'', text.font, ...systemFonts()}.toList();
    return AlertDialog(
      key: const ValueKey('text-content-dialog'),
      title: Text(l.textEdit),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('text-content-words'),
                controller: words,
                autofocus: true,
                minLines: 1,
                maxLines: 5,
                maxLength: LayerText.maxLength,
                decoration: InputDecoration(labelText: l.textWords),
                style: TextStyle(
                  fontFamily: text.font.isEmpty ? null : text.font,
                ),
              ),
              DropdownButtonFormField<String>(
                key: const ValueKey('text-content-font'),
                initialValue: text.font,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.textFont),
                items: [
                  for (final f in fonts)
                    DropdownMenuItem(
                      value: f,
                      child: Text(
                        f.isEmpty ? l.textDefaultFont : f,
                        style: TextStyle(fontFamily: f.isEmpty ? null : f),
                      ),
                    ),
                ],
                onChanged: (f) => setState(() => text = text.copyWith(font: f)),
              ),
              ValueSlider(
                id: 'text-content-size',
                label: l.textSize,
                value: text.size,
                min: 8,
                max: 600,
                toNumber: (v) => v,
                fromNumber: (n) => n,
                unit: 'px',
                onChanged: (v) => setState(() => text = text.copyWith(size: v)),
              ),
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('text-content-bold'),
                    isSelected: text.weight >= 600,
                    onPressed: () => setState(
                      () => text = text.copyWith(
                        weight: text.weight >= 600 ? 400 : 700,
                      ),
                    ),
                    icon: const Icon(Icons.format_bold_rounded),
                  ),
                  IconButton(
                    key: const ValueKey('text-content-italic'),
                    isSelected: text.italic,
                    onPressed: () => setState(
                      () => text = text.copyWith(italic: !text.italic),
                    ),
                    icon: const Icon(Icons.format_italic_rounded),
                  ),
                  const SizedBox(width: 8),
                  for (final (a, icon) in [
                    (TextAlignment.left, Icons.format_align_left_rounded),
                    (TextAlignment.center, Icons.format_align_center_rounded),
                    (TextAlignment.right, Icons.format_align_right_rounded),
                  ])
                    IconButton(
                      key: ValueKey('text-content-${a.name}'),
                      isSelected: text.alignment == a,
                      onPressed: () =>
                          setState(() => text = text.copyWith(alignment: a)),
                      icon: Icon(icon),
                    ),
                  const Spacer(),
                  InkWell(
                    key: const ValueKey('text-content-color'),
                    onTap: () => setState(() => picking = !picking),
                    child: Container(
                      width: 32,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Color(text.color),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
              if (picking)
                ColorPicker(
                  color: text.color,
                  onColor: (v) =>
                      setState(() => text = text.copyWith(color: v)),
                  recent: widget.recent,
                  hexField: const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('text-content-done'),
          onPressed: () {
            final w = words.text.trim();
            if (w.isEmpty) return;
            Navigator.pop(context, text.copyWith(text: w));
          },
          child: Text(l.done),
        ),
      ],
    );
  }
}
