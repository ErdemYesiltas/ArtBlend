// Builds the reference-layer demo drawing: run with
// `flutter test tool/reference_demo_test.dart`; writes
// ../../.qa/Referans-ornegi.artdoc and a PNG preview.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/data/document_package.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/png_bands.dart';
import 'package:atelier_studio/drawing/raster_cache.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/memory_storage.dart';

/// Black line art with closed areas: a house, its roof, door and window,
/// the sun, a hill and a flower.
Future<Uint8List> lineArt() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final pen = ui.Paint()
    ..color = const ui.Color(0xff1d1d1f)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 9
    ..strokeJoin = ui.StrokeJoin.round
    ..strokeCap = ui.StrokeCap.round;
  // Hill (closed with the canvas bottom).
  canvas.drawPath(
    ui.Path()
      ..moveTo(-10, 820)
      ..quadraticBezierTo(512, 660, 1034, 820)
      ..lineTo(1034, 1034)
      ..lineTo(-10, 1034)
      ..close(),
    pen,
  );
  // House body, roof, door, window.
  canvas.drawRect(const ui.Rect.fromLTWH(260, 450, 380, 320), pen);
  canvas.drawPath(
    ui.Path()
      ..moveTo(230, 455)
      ..lineTo(450, 250)
      ..lineTo(670, 455)
      ..close(),
    pen,
  );
  canvas.drawRect(const ui.Rect.fromLTWH(410, 590, 90, 180), pen);
  canvas.drawRect(const ui.Rect.fromLTWH(300, 510, 80, 80), pen);
  canvas.drawLine(const ui.Offset(340, 510), const ui.Offset(340, 590), pen);
  canvas.drawLine(const ui.Offset(300, 550), const ui.Offset(380, 550), pen);
  // Sun.
  canvas.drawCircle(const ui.Offset(820, 200), 90, pen);
  // Flower: five petals around a centre.
  const centre = ui.Offset(800, 640);
  for (var i = 0; i < 5; i++) {
    final a = i * 2 * math.pi / 5 - math.pi / 2;
    canvas.drawCircle(
      centre + ui.Offset(math.cos(a), math.sin(a)) * 46,
      30,
      pen,
    );
  }
  canvas.drawCircle(centre, 24, pen);
  canvas.drawLine(const ui.Offset(800, 664), const ui.Offset(800, 760), pen);
  final image = await recorder.endRecording().toImage(1024, 1024);
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  return encodeRgbaPng(data!.buffer.asUint8List(), 1024, 1024);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('build the reference layer demo', () async {
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    c.renameDocument('Referans örneği');
    final colours = c.document.activeLayer;
    c.updateLayer(colours.id, (l) => l.copyWith(name: 'Renkler'));
    await c.addImageLayer(await lineArt(), 'Çizgiler (referans)');
    final lines = c.document.activeLayer;
    c.toggleReferenceLayer(lines.id);
    // Colour goes on the empty layer under the lines.
    c.selectLayer(colours.id);
    for (final (point, color) in [
      (const ui.Offset(560, 700), 0xfff2c14e), // house wall
      (const ui.Offset(450, 380), 0xffd9534f), // roof
      (const ui.Offset(820, 200), 0xfff7a541), // sun
      (const ui.Offset(150, 950), 0xff6aa84f), // hill
    ]) {
      await c.colorDrop(point, color: color);
    }
    c.endFill();
    final document = c.document;
    await RasterAsset.hashAll([
      for (final layer in document.layers) ...?layer.raster?.tiles.values,
    ]);
    final blobs = <String, Uint8List>{};
    final manifest = document.toJson(blobs: blobs);
    final bytes = encodeDocumentPackage((manifest, blobs));
    await File('../../.qa/Referans-ornegi.artdoc').writeAsBytes(bytes);
    await File('../../.qa/referans-ornegi.png')
        .writeAsBytes(await renderDocumentPng(document, c.rasters.images));
    expect(document.layers.map((l) => (l.name, l.reference)), [
      ('Renkler', false),
      ('Çizgiler (referans)', true),
    ]);
    c.dispose();
  });
}
