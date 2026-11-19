import 'dart:isolate';
import 'dart:typed_data';

/// The area ColorDrop fills from ([seedX], [seedY]) in straight RGBA
/// [rgba]: pixels connected to the seed (4-neighbours) whose premultiplied
/// colour differs from the seed's by at most [threshold] (0–1, largest
/// channel difference), grown by [grow] pixels so the fill tucks under
/// anti-aliased line edges. Limited to [clip] coverage (one byte per pixel)
/// when given; the result is coverage too (0 or 255, the clip's own soft
/// edge kept). Pure and sendable: run it on a background isolate.
Uint8List floodFill(
  Uint8List rgba,
  int width,
  int height,
  int seedX,
  int seedY, {
  required double threshold,
  int grow = 1,
  Uint8List? clip,
}) {
  final n = width * height;
  final out = Uint8List(n);
  if (seedX < 0 || seedY < 0 || seedX >= width || seedY >= height) return out;
  if (clip != null && clip[seedY * width + seedX] == 0) return out;
  int pre(int i, int c) =>
      c == 3 ? rgba[i * 4 + 3] : rgba[i * 4 + c] * rgba[i * 4 + 3] ~/ 255;
  final seed = seedY * width + seedX;
  final target = [for (var c = 0; c < 4; c++) pre(seed, c)];
  final limit = (threshold.clamp(0.0, 1.0) * 255).round();
  bool matches(int i) {
    if (clip != null && clip[i] == 0) return false;
    for (var c = 0; c < 4; c++) {
      if ((pre(i, c) - target[c]).abs() > limit) return false;
    }
    return true;
  }

  // Scanline fill: one run per stack entry, no recursion.
  final stack = <int>[seed];
  out[seed] = 255;
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    final y = i ~/ width;
    var left = i, right = i;
    while (left % width > 0 && out[left - 1] == 0 && matches(left - 1)) {
      left--;
      out[left] = 255;
    }
    while (right % width < width - 1 &&
        out[right + 1] == 0 &&
        matches(right + 1)) {
      right++;
      out[right] = 255;
    }
    for (final dy in const [-1, 1]) {
      final ny = y + dy;
      if (ny < 0 || ny >= height) continue;
      var x = left - y * width;
      final end = right - y * width;
      while (x <= end) {
        final j = ny * width + x;
        if (out[j] == 0 && matches(j)) {
          out[j] = 255;
          stack.add(j);
          // Skip the rest of this run: its own scan reaches it.
          while (x <= end && out[ny * width + x] != 0) {
            x++;
          }
        } else {
          x++;
        }
      }
    }
  }
  for (var g = 0; g < grow; g++) {
    final grown = Uint8List.fromList(out);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * width + x;
        if (out[i] != 0) continue;
        if ((x > 0 && out[i - 1] != 0) ||
            (x < width - 1 && out[i + 1] != 0) ||
            (y > 0 && out[i - width] != 0) ||
            (y < height - 1 && out[i + width] != 0)) {
          grown[i] = 255;
        }
      }
    }
    out.setAll(0, grown);
  }
  if (clip != null) {
    for (var i = 0; i < n; i++) {
      if (out[i] != 0) out[i] = clip[i];
    }
  }
  return out;
}

/// [coverage] in [argb] as premultiplied RGBA, ready to draw over a layer.
Uint8List coverageToRgba(Uint8List coverage, int argb) {
  final rgba = Uint8List(coverage.length * 4);
  final r = (argb >> 16) & 0xff, g = (argb >> 8) & 0xff, b = argb & 0xff;
  final a = (argb >> 24) & 0xff;
  for (var i = 0; i < coverage.length; i++) {
    final c = coverage[i];
    if (c == 0) continue;
    final alpha = c * a ~/ 255;
    rgba
      ..[i * 4] = r * alpha ~/ 255
      ..[i * 4 + 1] = g * alpha ~/ 255
      ..[i * 4 + 2] = b * alpha ~/ 255
      ..[i * 4 + 3] = alpha;
  }
  return rgba;
}

/// Both steps of a ColorDrop off the UI isolate: the fill area of [rgba],
/// coloured in [argb] (premultiplied), or null when nothing is filled.
Uint8List? colorDropPixels(
  (Uint8List, int, int, int, int, double, Uint8List?, int) request,
) {
  final (rgba, width, height, x, y, threshold, clip, argb) = request;
  final area = floodFill(
    rgba,
    width,
    height,
    x,
    y,
    threshold: threshold,
    clip: clip,
  );
  if (!area.any((c) => c != 0)) return null;
  return coverageToRgba(area, argb);
}

/// [colorDropPixels] on a background isolate. Its own function: a closure
/// made inside the caller would share that context and could not be sent.
Future<Uint8List?> colorDropOffThread(
  (Uint8List, int, int, int, int, double, Uint8List?, int) request,
) => Isolate.run(() => colorDropPixels(request));
