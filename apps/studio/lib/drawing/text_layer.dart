import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../domain/layer_text.dart';

/// A text's laid-out lines (or columns, when vertical) and where they go.
class _Layout {
  _Layout(this.parts, this.bounds);
  final List<(TextPainter, Offset)> parts;
  final Rect bounds;
}

var _layouts = Expando<_Layout>();

/// Forgets laid-out text: after a font has loaded, text in it lays out anew.
void resetTextLayouts() => _layouts = Expando<_Layout>();

TextStyle _style(LayerText t) => TextStyle(
  fontFamily: t.font.isEmpty ? null : t.font,
  fontSize: t.size,
  fontWeight: FontWeight.values[(t.weight ~/ 100 - 1).clamp(0, 8)],
  fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
  letterSpacing: t.tracking * t.size,
  height: t.leading,
  decoration: t.underline ? TextDecoration.underline : TextDecoration.none,
  decorationColor: Color(t.color),
  foreground: Paint()
    ..color = Color(t.color)
    ..style = t.outline ? PaintingStyle.stroke : PaintingStyle.fill
    ..strokeWidth = math.max(1, t.size * .04),
);

_Layout _layout(LayerText t) => _layouts[t] ??= () {
  final style = _style(t);
  final lift = Offset(0, -t.baseline * t.size);
  if (!t.vertical) {
    final painter = TextPainter(
      text: TextSpan(text: t.shown, style: style),
      textAlign: switch (t.alignment) {
        TextAlignment.left => TextAlign.left,
        TextAlignment.center => TextAlign.center,
        TextAlignment.right => TextAlign.right,
        TextAlignment.justify => TextAlign.justify,
      },
      textDirection: TextDirection.ltr,
    )..layout(minWidth: t.width, maxWidth: t.width);
    return _Layout([
      (painter, t.origin + lift),
    ], Rect.fromLTWH(t.origin.dx, t.origin.dy, t.width, painter.height));
  }
  // Each line becomes a column of letters, columns left to right.
  final parts = <(TextPainter, Offset)>[];
  var x = t.origin.dx;
  var height = 0.0;
  for (final line in t.shown.split('\n')) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCodes(line.runes.expand((r) => [r, 10]))
            .trimRight(),
        style: style,
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    final width = math.max(painter.width, t.size * .6);
    parts.add((painter, Offset(x + (width - painter.width) / 2, t.origin.dy)));
    x += width + t.size * .2;
    height = math.max(height, painter.height);
  }
  return _Layout(
    [for (final (p, o) in parts) (p, o + lift)],
    Rect.fromLTRB(
      t.origin.dx,
      t.origin.dy,
      x - t.size * .2,
      t.origin.dy + height,
    ),
  );
}();

/// The text box: its width across, as tall as the text.
Rect textBounds(LayerText text) => _layout(text).bounds;

void paintLayerText(Canvas canvas, LayerText text) {
  for (final (painter, offset) in _layout(text).parts) {
    painter.paint(canvas, offset);
  }
}
