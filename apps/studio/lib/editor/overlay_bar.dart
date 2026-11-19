import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// A slim bar over the canvas, at its bottom (or under the toolbar): it
/// fades while the canvas is being drawn on, so the drawing shows through,
/// and comes back when the touch ends.
class OverlayBar extends StatelessWidget {
  const OverlayBar({
    super.key,
    required this.engaged,
    required this.children,
    this.top = false,
    this.maxWidth = 720,
    this.maxHeightFactor = .45,
  });

  /// True while a finger or the pen is on the canvas.
  final ValueListenable<bool> engaged;
  final List<Widget> children;
  final bool top;
  final double maxWidth;

  /// At most this share of the screen's height; more scrolls.
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, top ? 8 : 0, 12, top ? 0 : 8),
        child: ValueListenableBuilder<bool>(
          valueListenable: engaged,
          builder: (context, busy, child) => AnimatedOpacity(
            opacity: busy ? .25 : 1,
            duration: const Duration(milliseconds: 180),
            child: child,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
            ),
            child: Material(
              elevation: 4,
              color: scheme.surface.withValues(alpha: .94),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              // Tight icon buttons: a bar's row stays one line.
              child: IconButtonTheme(
                data: IconButtonThemeData(
                  style: IconButton.styleFrom(
                    minimumSize: const Size(36, 36),
                    padding: const EdgeInsets.all(6),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A hint, behind an ⓘ.
Widget barHint(String text) => Tooltip(
  message: text,
  triggerMode: TooltipTriggerMode.tap,
  showDuration: const Duration(seconds: 6),
  child: const Padding(
    padding: EdgeInsets.all(8),
    child: Icon(Icons.info_outline, size: 18),
  ),
);

/// Icon choices in one row, each named in its tooltip; [selected] is
/// highlighted.
Widget barChoices<T>({
  required Map<T, (String, IconData)> options,
  required T selected,
  required ValueChanged<T>? onSelected,
  String keyPrefix = 'choice',
}) => Wrap(
  spacing: 2,
  children: [
    for (final MapEntry(key: value, value: (name, icon)) in options.entries)
      Builder(
        builder: (context) => IconButton(
          key: ValueKey('$keyPrefix-${value is Enum ? value.name : value}'),
          tooltip: name,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            backgroundColor: value == selected
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
          ),
          onPressed: onSelected == null ? null : () => onSelected(value),
          icon: Icon(icon, size: 20),
        ),
      ),
  ],
);
