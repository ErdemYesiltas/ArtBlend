import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:atelier_studio/data/document_package.dart';
import 'package:atelier_studio/data/studio_storage.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/png_bands.dart';
import 'package:flutter_test/flutter_test.dart';

const size = TiledRaster.size;

RasterAsset tile(int shade) => RasterAsset(
  id: newId(),
  png: encodeRgbaPng(
    Uint8List(size * size * 4)..fillRange(0, size * 4 * 8, shade),
    size,
    size,
  ),
  width: size,
  height: size,
);

ArtDocument drawing(Map<int, RasterAsset> tiles) {
  final layer = ArtLayer(
    id: 'layer',
    name: 'Paint',
    raster: TiledRaster(TileGrid(CanvasSize.legacy), tiles),
  );
  return ArtDocument(
    id: 'drawing',
    name: 'Tiles',
    layers: [layer],
    activeLayerId: layer.id,
  );
}

Map<int, Uint8List> pngs(ArtDocument doc) => {
  for (final MapEntry(:key, :value) in doc.activeLayer.raster!.tiles.entries)
    key: value.png,
};

Future<Directory> tempDir() async {
  final dir = await Directory.systemTemp.createTemp('artblend-store-');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}

Set<String> tileFiles(Directory dir) {
  final tiles = Directory('${dir.path}/tiles');
  if (!tiles.existsSync()) return {};
  return {for (final entry in tiles.listSync()) entry.uri.pathSegments.last};
}

void main() {
  test(
    'a save writes only tiles that are new; unchanged ones are shared',
    () async {
      final dir = await tempDir();
      final storage = LocalStudioStorage(dir);
      final kept = tile(10), first = tile(20);
      final v1 = drawing({0: kept, 1: first});
      await storage.saveDocument(v1);
      expect(tileFiles(dir), hasLength(2));
      final written = File('${dir.path}/tiles/${kept.sha256}.png')
          .statSync()
          .modified;
      final v2 = drawing({0: kept, 1: tile(30), 5: tile(40)});
      await storage.saveDocument(v2);
      expect(tileFiles(dir), hasLength(4));
      expect(
        File('${dir.path}/tiles/${kept.sha256}.png').statSync().modified,
        written,
      );
      expect(await File('${dir.path}/current.artdoc').length(), lessThan(2048));
      final reopened = await LocalStudioStorage(dir).loadDocument();
      expect(pngs(reopened!), pngs(v2));
    },
  );

  test(
    'a save interrupted before its manifest keeps the previous drawing',
    () async {
      final dir = await tempDir();
      final storage = LocalStudioStorage(dir);
      final v1 = drawing({0: tile(10)});
      await storage.saveDocument(v1);
      storage.documentFile.fault = (step) async {
        if (step == 'temp') throw const FileSystemException('Disk full');
      };
      await expectLater(
        storage.saveDocument(drawing({0: tile(50), 3: tile(60)})),
        throwsA(isA<FileSystemException>()),
      );
      final reopened = await LocalStudioStorage(dir).loadDocument();
      expect(pngs(reopened!), pngs(v1));
      // The new tiles reached the disk but no manifest refers to them.
      expect(tileFiles(dir), hasLength(3));
      await LocalStudioStorage(dir).compact();
      expect(tileFiles(dir), {
        '${v1.activeLayer.raster!.tiles[0]!.sha256}.png',
      });
    },
  );

  test(
    'a damaged tile makes that copy unreadable and the backup opens',
    () async {
      final dir = await tempDir();
      final storage = LocalStudioStorage(dir);
      final v1 = drawing({0: tile(10)});
      await storage.saveDocument(v1);
      final damaged = tile(70);
      await storage.saveDocument(drawing({0: damaged}));
      final file = File('${dir.path}/tiles/${damaged.sha256}.png');
      final bytes = await file.readAsBytes();
      bytes[bytes.length ~/ 2] ^= 0xff;
      await file.writeAsBytes(bytes);
      final fresh = LocalStudioStorage(dir);
      final reopened = await fresh.loadDocument();
      expect(pngs(reopened!), pngs(v1));
      expect(fresh.documentFile.recovered, isTrue);
    },
  );

  test('compaction keeps tiles of recovery copies and stops on an unreadable '
      'manifest', () async {
    final dir = await tempDir();
    final storage = LocalStudioStorage(dir);
    final v1 = drawing({0: tile(10)}), v2 = drawing({0: tile(11)});
    await storage.saveDocument(v1);
    await storage.saveDocument(v2);
    await storage.saveDocument(drawing({0: tile(12)}));
    // current: v3, current.bak: v2; v1's tile is referenced by nothing.
    expect(tileFiles(dir), hasLength(3));
    await storage.compact();
    expect(
      tileFiles(dir).contains('${v1.activeLayer.raster!.tiles[0]!.sha256}.png'),
      isFalse,
    );
    expect(
      tileFiles(dir).contains('${v2.activeLayer.raster!.tiles[0]!.sha256}.png'),
      isTrue,
    );
    await storage.saveDocument(drawing({0: tile(13)}));
    await File('${dir.path}/documents/broken.artdoc')
        .writeAsString('{not json');
    final before = tileFiles(dir);
    await LocalStudioStorage(dir).compact();
    expect(tileFiles(dir), before);
  });

  test('a single-JSON drawing from earlier versions opens and is rewritten '
      'as a manifest with tiles', () async {
    final dir = await tempDir();
    final v1 = drawing({2: tile(90)});
    await File('${dir.path}/current.artdoc')
        .writeAsString(jsonEncode(v1.toJson()));
    final storage = LocalStudioStorage(dir);
    final opened = await storage.loadDocument();
    expect(pngs(opened!), pngs(v1));
    await storage.saveDocument(opened);
    final manifest = await File('${dir.path}/current.artdoc').readAsString();
    expect(manifest, isNot(contains('"png"')));
    expect(tileFiles(dir), hasLength(1));
    expect(pngs((await LocalStudioStorage(dir).loadDocument())!), pngs(v1));
  });

  test('a drawing exports as one package and opens again; a tampered tile '
      'is refused', () async {
    final doc = drawing({0: tile(10), 7: tile(20)});
    final blobs = <String, Uint8List>{};
    final package = encodeDocumentPackage((doc.toJson(blobs: blobs), blobs));
    final opened = decodeDocumentFile(package);
    expect(pngs(opened), pngs(doc));
    // Earlier single-JSON exports still open.
    expect(
      pngs(decodeDocumentFile(utf8.encode(jsonEncode(doc.toJson())))),
      pngs(doc),
    );
    final archive = ZipDecoder().decodeBytes(package);
    final tampered = Archive();
    var altered = false;
    for (final file in archive.files) {
      final content = Uint8List.fromList(file.content);
      if (file.name.startsWith('tiles/') && !altered) {
        content[content.length ~/ 2] ^= 0xff;
        altered = true;
      }
      tampered.addFile(ArchiveFile.bytes(file.name, content));
    }
    expect(
      () => decodeDocumentFile(ZipEncoder().encodeBytes(tampered)),
      throwsFormatException,
    );
  });
}
