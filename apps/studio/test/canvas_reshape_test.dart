import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/drawing/brush_engine.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

Future<Uint8List> shown(StudioController c) async {
  final recorder = ui.PictureRecorder();
  final doc = c.document.copyWith(backgroundHidden: true);
  paintDocument(
    ui.Canvas(recorder),
    doc,
    FreehandBrushEngine(),
    rasterImages: c.rasters.images,
  );
  final image = await recorder.endRecording().toImage(
    doc.dimensions.width,
    doc.dimensions.height,
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

int alpha(StudioController c, Uint8List pixels, int x, int y) =>
    pixels[(y * c.document.dimensions.width + x) * 4 + 3];

/// A red square at (100, 100)–(300, 300) on the default canvas.
Future<StudioController> square() async {
  final c = StudioController(storage: MemoryStorage());
  await c.initialize();
  c.selectColor(0xffff0000);
  c.setSelection(
    SelectionRegion.rectangle(const Rect.fromLTWH(100, 100, 200, 200)),
  );
  await c.fillActiveLayer();
  c.setSelection(null);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('crop cuts and grows the canvas; masks and saved selections '
      'follow; undo brings the old size back', () async {
    final c = await square();
    addTearDown(c.dispose);
    final before = c.document.dimensions;
    c.updateLayer(
      c.document.activeLayerId,
      (l) => l.copyWith(
        mask: SelectionRegion.rectangle(const Rect.fromLTWH(0, 0, 200, 1000)),
      ),
    );
    c.setSelection(
      SelectionRegion.rectangle(const Rect.fromLTWH(150, 150, 50, 50)),
    );
    c.saveSelection();
    await c.cropCanvas(const Rect.fromLTWH(100, 100, 300, 250));
    expect(c.document.dimensions, const CanvasSize(300, 250));
    var pixels = await shown(c);
    expect(alpha(c, pixels, 50, 50), 255);
    expect(alpha(c, pixels, 150, 50), 0, reason: 'the mask moved too');
    expect(alpha(c, pixels, 250, 220), 0);
    expect(
      c.document.savedSelections.single.path.contains(const Offset(70, 70)),
      isTrue,
    );
    final back = ArtDocument.fromJson(c.document.toJson());
    expect(back.dimensions, const CanvasSize(300, 250));
    c.undo();
    await c.settleStroke();
    expect(c.document.dimensions, before);

    // Grown on every side: the square sits further in.
    c.updateLayer(c.document.activeLayerId, (l) => l.copyWith(clearMask: true));
    await c.cropCanvas(
      Rect.fromLTWH(-50, -50, before.width + 100.0, before.height + 100.0),
    );
    pixels = await shown(c);
    expect(alpha(c, pixels, 160, 160), 255);
    expect(alpha(c, pixels, 120, 120), 0);
  });

  test('resample scales; rotate and flip move the pixels', () async {
    final c = await square();
    addTearDown(c.dispose);
    final size = c.document.dimensions;
    await c.resampleCanvas(CanvasSize(size.width ~/ 2, size.height ~/ 2));
    var pixels = await shown(c);
    expect(alpha(c, pixels, 75, 75), 255);
    expect(alpha(c, pixels, 160, 160), 0);
    c.undo();
    await c.settleStroke();

    await c.rotateCanvas(clockwise: true);
    expect(c.document.dimensions, CanvasSize(size.height, size.width));
    pixels = await shown(c);
    // (x, y) went to (H − y, x): the square is now near the right edge.
    expect(alpha(c, pixels, size.height - 200, 200), 255);
    expect(alpha(c, pixels, 200, 200), 0);
    c.undo();
    await c.settleStroke();

    await c.flipCanvas(horizontal: true);
    pixels = await shown(c);
    expect(alpha(c, pixels, size.width - 200, 200), 255);
    expect(alpha(c, pixels, 200, 200), 0);
  });

  test('a selection cut to the canvas keeps what lies inside', () {
    final region = SelectionRegion.rectangle(
      const Rect.fromLTWH(10, 10, 100, 100),
    );
    final moved = region.mapped((p) => p - const Offset(50, 50))!;
    expect(moved.path.contains(const Offset(30, 30)), isTrue);
    expect(moved.path.getBounds(), const Rect.fromLTWH(0, 0, 60, 60));
    expect(region.mapped((p) => p - const Offset(500, 500)), isNull);
  });
}
