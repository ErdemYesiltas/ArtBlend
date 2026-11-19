import 'dart:typed_data';
import 'dart:ui' as ui;

import '../domain/document.dart';
import 'brush_engine.dart';

/// The whole document as displayed (paper, every visible layer, masks and
/// blend modes), as premultiplied RGBA at document resolution.
Future<Uint8List> renderDocumentRgba(
  ArtDocument document,
  Map<RasterAsset, ui.Image> images,
) async {
  final recorder = ui.PictureRecorder();
  paintDocument(
    ui.Canvas(recorder),
    document,
    FreehandBrushEngine(),
    rasterImages: images,
  );
  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(
      document.dimensions.width,
      document.dimensions.height,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw StateError('Canvas readback failed');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image?.dispose();
    picture.dispose();
  }
}

/// Opaque ARGB colour of one pixel of a premultiplied RGBA buffer; the point
/// is clamped to the canvas. Translucent paper is un-premultiplied.
int sampleOpaqueColor(Uint8List rgba, CanvasSize dimensions, ui.Offset point) {
  final x = point.dx.floor().clamp(0, dimensions.width - 1);
  final y = point.dy.floor().clamp(0, dimensions.height - 1);
  final i = (y * dimensions.width + x) * 4;
  final a = rgba[i + 3];
  int channel(int v) => a == 0 ? 0 : (v * 255 / a).round().clamp(0, 255);
  return 0xff000000 |
      channel(rgba[i]) << 16 |
      channel(rgba[i + 1]) << 8 |
      channel(rgba[i + 2]);
}
