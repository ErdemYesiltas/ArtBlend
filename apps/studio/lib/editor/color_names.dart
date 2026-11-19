import 'package:material_ui/material_ui.dart' show Color, HSLColor;

import '../l10n/app_localizations.dart';

/// A colour in words, for colour cards and spoken colour notes: its hue's
/// name with light, dark or greyish before it, or a grey's name.
String colorName(AppLocalizations l, int argb) {
  final hsl = HSLColor.fromColor(Color(argb));
  final light = hsl.lightness, saturation = hsl.saturation, hue = hsl.hue;
  if (saturation < .1 || light < .06 || light > .97) {
    if (light < .12) return l.colorBlack;
    if (light > .92) return l.colorWhite;
    if (light < .38) return '${l.colorDark} ${l.colorGrey}';
    if (light > .7) return '${l.colorLight} ${l.colorGrey}';
    return l.colorGrey;
  }
  // Dark, muted oranges and reds are browns.
  final brown =
      (hue >= 10 && hue < 50) && light < .45 && saturation < .75 ||
      (hue < 10 || hue >= 345) && light < .3 && saturation < .5;
  final noun = brown
      ? l.colorBrown
      : switch (hue) {
          < 15 => l.colorRed,
          < 40 => l.colorOrange,
          < 65 => l.colorYellow,
          < 90 => l.colorLime,
          < 160 => l.colorGreen,
          < 190 => l.colorTurquoise,
          < 250 => l.colorBlue,
          < 290 => l.colorPurple,
          < 330 => l.colorMagenta,
          < 345 => l.colorPink,
          _ => l.colorRed,
        };
  final modifier = saturation < .3
      ? l.colorGreyish
      : light < .3
      ? l.colorDark
      : light > .75
      ? l.colorLight
      : null;
  return modifier == null ? noun : '$modifier $noun';
}
