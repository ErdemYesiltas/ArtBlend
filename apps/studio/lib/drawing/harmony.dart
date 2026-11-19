/// Procreate's colour harmonies.
enum HarmonyMode {
  complementary,
  splitComplementary,
  analogous,
  triadic,
  tetradic,
}

/// The hues (degrees) [mode] pairs with [hue], [hue] itself first.
List<double> harmonyHues(HarmonyMode mode, double hue) {
  final offsets = switch (mode) {
    HarmonyMode.complementary => const [0, 180],
    HarmonyMode.splitComplementary => const [0, 150, 210],
    HarmonyMode.analogous => const [0, -30, 30],
    HarmonyMode.triadic => const [0, 120, 240],
    HarmonyMode.tetradic => const [0, 90, 180, 270],
  };
  return [for (final o in offsets) (hue + o) % 360];
}

/// A double tap on the disc: [hue] to the nearest of 12 steps, and
/// saturation and brightness to the nearest quarter.
(double, double, double) snapToPreset(
  double hue,
  double saturation,
  double value,
) {
  double quarter(double v) => (v * 4).round() / 4;
  return ((hue / 30).round() * 30 % 360, quarter(saturation), quarter(value));
}
