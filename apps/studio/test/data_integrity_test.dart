import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:atelier_studio/data/studio_storage.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/png_bands.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

Future<Directory> tempDir() async {
  final dir = await Directory.systemTemp.createTemp('artblend-integrity-');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}

FileSystemException diskFull(String path) => FileSystemException(
  'No space left on device',
  path,
  const OSError('No space left on device', 28),
);

void stroke(StudioController c, double y) {
  c.beginStroke(InkPoint(100, y, .5), simulatePressure: false);
  c.appendPoint(InkPoint(900, y, .5));
  c.finishStroke();
}

void main() {
  test('saving writes one small manifest twice and each tile once, encoded in the background', () async {
    final rgba = Uint8List(256 * 256 * 4)..fillRange(0, 4096, 200);
    final layer = ArtLayer(id: 'l', name: 'Raster').copyWith(
      raster: TiledRaster(TileGrid(CanvasSize.legacy), {
        5: RasterAsset(
          id: 'r',
          png: encodeRgbaPng(rgba, 256, 256),
          width: 256,
          height: 256,
        ),
      }),
    );
    final doc = ArtDocument.empty().copyWith(
      layers: [layer],
      activeLayerId: 'l',
    );
    final encoded = await AtomicJsonFile.encode(doc.toJson(deferPng: true));
    expect(encoded, utf8.encode(jsonEncode(doc.toJson())));
    final dir = await tempDir();
    final storage = LocalStudioStorage(dir);
    await storage.saveDocument(doc);
    // Saved as a manifest: same bytes in both places, the tile outside it.
    final blobs = <String, Uint8List>{};
    final manifest = await AtomicJsonFile.encode(
      doc.toJson(deferPng: true, blobs: blobs),
    );
    expect(await File('${dir.path}/current.artdoc').readAsBytes(), manifest);
    expect(await storage.archive(doc.id).file.readAsBytes(), manifest);
    expect(manifest.length, lessThan(1024));
    final tile = blobs.keys.single;
    expect(
      await File('${dir.path}/tiles/$tile.png').readAsBytes(),
      layer.raster!.tiles[5]!.png,
    );
  });

  test(
    'writes land in call order even when encodings finish out of order',
    () async {
      final dir = await tempDir();
      final file = AtomicJsonFile(File('${dir.path}/order.json'));
      final first = Completer<Uint8List>();
      final writes = [
        file.writeEncoded(first.future),
        file.writeEncoded(
          Future.value(Uint8List.fromList(utf8.encode('{"n":2}'))),
        ),
      ];
      first.complete(Uint8List.fromList(utf8.encode('{"n":1}')));
      await Future.wait(writes);
      expect(await file.read(), {'n': 2});
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();

  test('a full disk during the temp write leaves the main file and no partial copy', () async {
    final dir = await tempDir();
    final file = File('${dir.path}/doc.json');
    final store = AtomicJsonFile(file);
    await store.write({'revision': 1});
    store.fault = (step) async {
      if (step != 'temp') return;
      final temp = File('${file.path}.tmp');
      // Half the bytes made it before the device filled up.
      final bytes = await temp.readAsBytes();
      await temp.writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));
      throw diskFull(temp.path);
    };
    await expectLater(
      store.write({'revision': 2}),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File('${file.path}.tmp').exists(), isFalse);
    expect(await AtomicJsonFile(file).read(), {'revision': 1});
    store.fault = null;
    await store.write({'revision': 3});
    expect(await AtomicJsonFile(file).read(), {'revision': 3});
  });

  test(
    'a crash between backup and promotion restores the newest complete copy',
    () async {
      final dir = await tempDir();
      final file = File('${dir.path}/doc.json');
      final store = AtomicJsonFile(file)
        ..fault = (step) async {
          if (step == 'promote') throw StateError('process killed');
        };
      final first = AtomicJsonFile(file);
      await first.write({'revision': 1});
      await expectLater(store.write({'revision': 2}), throwsStateError);
      expect(await file.exists(), isFalse);
      // A fresh launch reads .tmp and finishes the promotion.
      final relaunch = AtomicJsonFile(file);
      expect(await relaunch.read(), {'revision': 2});
      expect(await file.exists(), isTrue);
      expect(relaunch.recovered, isFalse);
      expect(jsonDecode(await File('${file.path}.bak').readAsString()), {
        'revision': 1,
      });
      // Even a failing next write cannot lose revision 2 now.
      relaunch.fault = (step) async {
        if (step == 'temp') throw diskFull(file.path);
      };
      await expectLater(
        relaunch.write({'revision': 3}),
        throwsA(isA<FileSystemException>()),
      );
      expect(await AtomicJsonFile(file).read(), {'revision': 2});
    },
  );

  test(
    'a valid JSON file that is not a valid drawing falls back to the backup',
    () async {
      final dir = await tempDir();
      final storage = LocalStudioStorage(dir);
      final document = ArtDocument.empty(name: 'Kept');
      await storage.saveDocument(document);
      await storage.saveDocument(
        document.copyWith(name: 'Newest', revision: 1),
      );
      await storage.documentFile.file.writeAsString(
        jsonEncode({'format': 'other'}),
      );
      final restored = await LocalStudioStorage(dir).loadDocument();
      expect(restored!.name, 'Kept');
    },
  );

  test(
    'saving stays consistent when the archive write fails and repairs it later',
    () async {
      final dir = await tempDir();
      final storage = LocalStudioStorage(dir);
      final c = StudioController(storage: storage);
      await c.initialize();
      stroke(c, 100);
      await c.save();
      expect(c.saveState, SaveState.saved);
      stroke(c, 200);
      final archive = storage.archive(c.document.id);
      archive.fault = (step) async {
        if (step == 'temp') throw diskFull(archive.file.path);
      };
      await c.save();
      expect(c.saveState, SaveState.failed);
      expect(c.error, contains('No space left'));
      // The current file already holds the newest drawing.
      final reopened = await LocalStudioStorage(dir).loadDocument();
      expect(reopened!.activeLayer.strokes.length, 2);
      archive.fault = null;
      await c.save();
      expect(c.saveState, SaveState.saved);
      final gallery = await LocalStudioStorage(dir).listDocuments();
      expect(gallery.documents.single.activeLayer.strokes.length, 2);
      c.dispose();
    },
  );

  test(
    'the editor keeps the last saved drawing when the disk is full',
    () async {
      final dir = await tempDir();
      final storage = LocalStudioStorage(dir);
      final c = StudioController(storage: storage);
      await c.initialize();
      stroke(c, 100);
      await c.save();
      storage.documentFile.fault = (step) async {
        if (step == 'temp') throw diskFull(storage.documentFile.file.path);
      };
      stroke(c, 200);
      await c.save();
      expect(c.saveState, SaveState.failed);
      // In memory the edit is intact; on disk the previous snapshot is.
      expect(c.document.activeLayer.strokes.length, 2);
      expect(
        (await LocalStudioStorage(
          dir,
        ).loadDocument())!.activeLayer.strokes.length,
        1,
      );
      final leftovers = dir
          .listSync(recursive: true)
          .where((e) => e.path.endsWith('.tmp'));
      expect(leftovers, isEmpty);
      storage.documentFile.fault = null;
      await c.save();
      expect(
        (await LocalStudioStorage(
          dir,
        ).loadDocument())!.activeLayer.strokes.length,
        2,
      );
      c.dispose();
    },
  );

  test(
    'one unreadable archive does not hide the rest of the gallery',
    () async {
      final dir = await tempDir();
      final storage = LocalStudioStorage(dir);
      await storage.saveDocument(ArtDocument.empty(name: 'One'));
      await storage.saveDocument(ArtDocument.empty(name: 'Two'));
      final broken = File('${storage.documentsDirectory.path}/broken.artdoc');
      await broken.writeAsString('{"format": "atelier.document", "version"');
      final listing = await LocalStudioStorage(dir).listDocuments();
      expect(listing.documents.map((d) => d.name).toSet(), {'One', 'Two'});
      expect(listing.unreadable, ['broken.artdoc']);
      expect(
        await broken.readAsString(),
        '{"format": "atelier.document", "version"',
      );
    },
  );

  test('an unreadable library locks itself instead of blocking drawing or being overwritten', () async {
    final dir = await tempDir();
    final storage = LocalStudioStorage(dir);
    await storage.libraryFile.file.parent.create(recursive: true);
    const damaged = '{"version": 1, "brushes": [{"name": 3}]';
    await storage.libraryFile.file.writeAsString(damaged);
    final c = StudioController(storage: storage);
    await c.initialize();
    expect(c.initialized, isTrue);
    expect(c.libraryLocked, isTrue);
    expect(c.brushes, isNotEmpty);
    expect(() => c.addBrushes([initialBrushes.first]), throwsStateError);
    expect(
      () => c.addPalettes([
        ColorPalette(id: 'p', name: 'p', colors: [0xff000000]),
      ]),
      throwsStateError,
    );
    stroke(c, 100);
    await c.save();
    expect(c.saveState, SaveState.saved);
    expect(await storage.libraryFile.file.readAsString(), damaged);
    c.dispose();
  });

  test('palette import applies all palettes in one change', () async {
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    addTearDown(c.dispose);
    final before = c.palettes.length;
    c.addPalettes([
      ColorPalette(id: 'a', name: 'A', colors: [0xff000000]),
      ColorPalette(id: 'b', name: 'B', colors: [0xffffffff]),
    ]);
    expect(c.palettes.length, before + 2);
    expect(c.libraryDirty, isTrue);
  });

  testWidgets('gallery and library panels explain unreadable files', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = _DamagedStorage();
    final c = StudioController(storage: storage);
    await c.initialize();
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    c.setPanel(EditorPanel.gallery);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gallery-unreadable')), findsOneWidget);
    expect(
      find.textContaining('1 drawing file could not be read'),
      findsOneWidget,
    );
    c.setPanel(EditorPanel.brushes);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-unreadable')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}

class _DamagedStorage extends MemoryStorage {
  @override
  Future<Map<String, dynamic>?> loadLibrary() async =>
      throw const FormatException('Cannot recover saved data');
  @override
  Future<GalleryListing> listDocuments() async =>
      GalleryListing(documents.values.toList(), ['broken.artdoc']);
}
