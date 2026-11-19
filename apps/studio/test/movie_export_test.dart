import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:atelier_studio/data/studio_storage.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/movie.dart';
import 'package:atelier_studio/drawing/png_bands.dart';
import 'package:atelier_studio/movie/movie_controller.dart';
import 'package:atelier_studio/movie/movie_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/memory_storage.dart';

/// A drawing of the whole 256×256 tile filled red (straight alpha).
ArtDocument red() {
  const n = TiledRaster.size;
  final rgba = Uint8List(n * n * 4);
  for (var i = 0; i < n * n; i++) {
    rgba.setAll(i * 4, [255, 0, 0, 255]);
  }
  final layer = ArtLayer(
    id: 'ink',
    name: 'Ink',
    raster: TiledRaster(TileGrid(const CanvasSize(100, 100)), {
      0: RasterAsset(
        id: newId(),
        png: encodeRgbaPng(rgba, n, n),
        width: n,
        height: n,
      ),
    }),
  );
  return ArtDocument(
    id: 'd',
    name: 'Red',
    dimensions: const CanvasSize(100, 100),
    layers: [layer],
    activeLayerId: 'ink',
    backgroundHidden: true,
  );
}

MovieController film({bool transparent = false, StudioStorage? storage}) {
  final c = MovieController(
    storage: storage ?? MemoryStorage(),
    movie: MovieDocument(
      id: 'm',
      name: 'Film',
      width: 200,
      height: 100,
      fps: 10,
      frames: 4,
      background: 0xff0000ff,
      transparent: transparent,
      tracks: [
        MovieTrack(
          id: 't',
          name: 'Ink',
          kind: TrackKind.drawing,
          contents: [
            MovieContent(
              id: 'c',
              name: 'Red',
              kind: TrackKind.drawing,
              start: 1,
              length: 2,
              width: 100,
              height: 100,
            ),
          ],
        ),
      ],
    ),
  );
  c.drawings['c'] = red();
  return c;
}

List<int> at(img.Image image, int x, int y) {
  final p = image.getPixel(x, y);
  return [p.r.toInt(), p.g.toInt(), p.b.toInt(), p.a.toInt()];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('frames render as in the file: the stage colour, the drawing in the '
      'middle, only while it is on', () async {
    final c = film();
    addTearDown(c.dispose);
    final e = MovieExporter(c);
    final png = await e.export(const MovieExportOptions(MovieFormat.frame));
    expect(at(img.decodePng(png)!, 100, 50), [
      0,
      0,
      255,
      255,
    ], reason: 'frame 0: the content is not on yet');
    c.seek(1);
    final on = img.decodePng(
      await e.export(
        const MovieExportOptions(MovieFormat.frame, preview: true),
      ),
    )!;
    expect((on.width, on.height), (100, 50));
    expect(at(on, 50, 25), [255, 0, 0, 255]);
    expect(at(on, 5, 25), [0, 0, 255, 255]);
  });

  test('a transparent movie: a GIF keeps the see-through stage, frames '
      'for every frame; PNG frames come zipped in order', () async {
    final c = film(transparent: true);
    addTearDown(c.dispose);
    final e = MovieExporter(c);
    final gif = img.decodeGif(
      await e.export(const MovieExportOptions(MovieFormat.gif, gifColors: 16)),
    )!;
    expect(gif.numFrames, 4);
    expect(at(gif.frames[1], 100, 50).take(3), [255, 0, 0]);
    expect(at(gif.frames[1], 10, 50)[3], 0, reason: 'left see-through');

    final zip = ZipDecoder().decodeBytes(
      await e.export(const MovieExportOptions(MovieFormat.png)),
    );
    expect(
      [for (final f in zip.files) f.name],
      ['00001.png', '00002.png', '00003.png', '00004.png'],
    );
    final tga = ZipDecoder().decodeBytes(
      await e.export(const MovieExportOptions(MovieFormat.tga, preview: true)),
    );
    expect(tga.files.first.name, '00001.tga');
    expect(img.decodeTga(tga.files[1].content)!.width, 100);
  });

  test('a project file carries the movie, its drawings and media to another '
      'Theater', () async {
    final dir = await Directory.systemTemp.createTemp('project');
    addTearDown(() => dir.delete(recursive: true));
    final source = LocalStudioStorage(Directory('${dir.path}/a'));
    final sound = File('${dir.path}/beep.wav')..writeAsBytesSync([1, 2, 3]);
    final mediaId = await source.importMedia(sound.path);
    final c = film(storage: source);
    addTearDown(c.dispose);
    c.edit(
      c.movie.copyWith(
        tracks: [
          ...c.movie.tracks,
          MovieTrack(
            id: 's',
            name: 'Sound',
            kind: TrackKind.audio,
            contents: [
              MovieContent(
                id: 'snd',
                name: 'Beep',
                kind: TrackKind.audio,
                start: 0,
                length: 4,
                mediaId: mediaId,
              ),
            ],
          ),
        ],
      ),
    );
    final bytes = await MovieExporter(c)
        .export(const MovieExportOptions(MovieFormat.project));
    final package = ZipDecoder().decodeBytes(bytes);
    expect(
      jsonDecode(
        utf8.decode(package.findFile('movie.json')!.content),
      )['format'],
      'artblend.movie-package',
    );

    final target = LocalStudioStorage(Directory('${dir.path}/b'));
    final movie = (await importProject(bytes, target, dir))!;
    expect(movie.id, isNot('m'));
    expect(movie.tracks.map((t) => t.name), ['Ink', 'Sound']);
    final newMedia = movie.tracks.last.contents.single.mediaId!;
    expect(newMedia, isNot(mediaId));
    expect(File((await target.mediaPath(newMedia))!).readAsBytesSync(), [
      1,
      2,
      3,
    ]);
    final drawing = (await target.loadMovieDrawings(movie.id))['c']!;
    expect(
      drawing.layers.single.raster!.tiles[0]!.png,
      red().layers.single.raster!.tiles[0]!.png,
    );
    expect(await importProject(Uint8List(10), target, dir), isNull);
  });
}
