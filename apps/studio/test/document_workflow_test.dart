import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:atelier_studio/data/studio_storage.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/brush_engine.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_storage.dart';

void stroke(StudioController c, double y) {
  c.beginStroke(InkPoint(100, y, .5), simulatePressure: false);
  c.appendPoint(InkPoint(900, y, .5));
  c.finishStroke();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('switching drawings preserves both independently across application restart', () async {
    final dir = await Directory.systemTemp.createTemp('atelier-gallery-test-');
    addTearDown(() => dir.delete(recursive: true));
    final c = StudioController(storage: LocalStudioStorage(dir));
    await c.initialize();
    stroke(c, 100);
    final firstId = c.document.id;
    await c.replaceDocument(ArtDocument.empty(name: 'Second drawing'));
    stroke(c, 200);
    await c.save();
    c.dispose();
    final reopened = LocalStudioStorage(dir);
    expect((await reopened.loadDocument())!.name, 'Second drawing');
    final gallery = (await reopened.listDocuments()).documents;
    expect(gallery.length, 2);
    expect(
      gallery
          .firstWhere((d) => d.id == firstId)
          .activeLayer
          .strokes
          .single
          .points
          .first
          .y,
      100,
    );
  });
  test('drawing, layer deletion, undo/redo and disk round-trip preserve editable data', () async {
    final storage = MemoryStorage();
    final c = StudioController(storage: storage);
    await c.initialize();
    stroke(c, 100);
    final bottom = c.document.activeLayerId;
    c.addLayer('Foreground');
    final top = c.document.activeLayerId;
    stroke(c, 200);
    c.deleteLayer(top);
    c.undo();
    expect(c.document.activeLayerId, top);
    expect(c.document.activeLayer.strokes.length, 1);
    c.undo();
    expect(c.document.activeLayer.strokes, isEmpty);
    c.undo();
    expect(c.document.activeLayerId, bottom);
    c.redo();
    c.redo();
    expect(c.document.activeLayer.strokes.length, 1);
    await c.save();
    final roundTrip = ArtDocument.fromJson(
      jsonDecode(jsonEncode(storage.document!.toJson())),
    );
    expect(roundTrip.layers.length, 2);
    expect(roundTrip.activeLayerId, top);
    expect(roundTrip.layers.first.strokes.first.points.last.x, 900);
    c.dispose();
  });

  test('locked and hidden layers never accept strokes', () async {
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    final id = c.document.activeLayerId;
    c.updateLayer(id, (l) => l.copyWith(locked: true));
    expect(
      c.beginStroke(const InkPoint(1, 1, .5), simulatePressure: false),
      false,
    );
    c.updateLayer(id, (l) => l.copyWith(locked: false, visible: false));
    expect(
      c.beginStroke(const InkPoint(1, 1, .5), simulatePressure: false),
      false,
    );
    c.dispose();
  });

  test('an older in-flight save never marks a newer edit as saved', () async {
    final storage = BlockingStorage();
    final c = StudioController(storage: storage);
    await c.initialize();
    stroke(c, 100);
    final first = c.save();
    await storage.entered.future;
    stroke(c, 200);
    storage.release.complete();
    await first;
    expect(c.saveState, SaveState.pending);
    await c.save();
    expect(c.saveState, SaveState.saved);
    expect(storage.document!.activeLayer.strokes.length, 2);
    c.dispose();
  });

  test(
    'corrupt startup data is preserved and cannot be overwritten by autosave',
    () async {
      final storage = FailingStorage();
      final c = StudioController(storage: storage);
      await c.initialize();
      expect(c.initialized, false);
      await c.save();
      expect(storage.writes, 0);
      c.dispose();
    },
  );

  test(
    'atomic storage recovers the prior snapshot and preserves it during repair',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'atelier-storage-test-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/current.json');
      final store = AtomicJsonFile(file);
      await store.write({'revision': 1});
      await store.write({'revision': 2});
      await file.writeAsString('{incomplete');
      expect(await store.read(), {'revision': 1});
      expect(store.recovered, true);
      await store.write({'revision': 3});
      expect(jsonDecode(await File('${file.path}.bak').readAsString()), {
        'revision': 1,
      });
      expect(await store.read(), {'revision': 3});
      await Future.wait([
        store.write({'revision': 4}),
        store.write({'revision': 5}),
      ]);
      expect(await store.read(), {'revision': 5});
    },
  );

  test('eraser only clears its own layer and reveals paint below it', () async {
    InkStroke line(String id, int color, {bool eraser = false}) => InkStroke(
      id: id,
      points: const [InkPoint(100, 512, .5), InkPoint(924, 512, .5)],
      color: color,
      size: 100,
      opacity: 1,
      thinning: 0,
      eraser: eraser,
    );
    final bottom = ArtLayer(
      id: 'bottom',
      name: 'Bottom',
      strokes: [line('red', 0xffff0000)],
    );
    final top = ArtLayer(
      id: 'top',
      name: 'Top',
      strokes: [
        line('blue', 0xff0000ff),
        line('erase', 0xff000000, eraser: true),
      ],
    );
    final document = ArtDocument(
      id: 'doc',
      name: 'Test',
      layers: [bottom, top],
      activeLayerId: 'top',
    );
    final recorder = ui.PictureRecorder();
    paintDocument(ui.Canvas(recorder), document, FreehandBrushEngine());
    final picture = recorder.endRecording();
    final image = await picture.toImage(1024, 1024);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    final i = (512 * 1024 + 512) * 4;
    expect(data!.getUint8(i), 255);
    expect(data.getUint8(i + 2), 0);
  });
}

class BlockingStorage extends MemoryStorage {
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<void> saveDocument(ArtDocument value) async {
    if (!entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    await super.saveDocument(value);
  }
}

class FailingStorage extends MemoryStorage {
  int writes = 0;
  @override
  Future<ArtDocument?> loadDocument() =>
      throw const FormatException('Corrupt file');
  @override
  Future<void> saveDocument(ArtDocument value) async {
    writes++;
  }
}
