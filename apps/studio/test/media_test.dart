import 'dart:io';
import 'dart:typed_data';

import 'package:atelier_studio/data/import_formats.dart';
import 'package:atelier_studio/data/media.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/movie.dart';
import 'package:atelier_studio/movie/media_cache.dart';
import 'package:atelier_studio/movie/movie_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/memory_storage.dart';

/// One second of a steady tone level [v] (both channels).
Int16List level(int v, {double seconds = 1}) =>
    Int16List.fromList(List.filled((audioRate * seconds).round() * 2, v));

class FakeTools extends MediaTools {
  FakeTools(this.dir);
  final Directory dir;
  @override
  Future<MediaInfo?> probe(String path) async => MediaInfo(
    width: 320,
    height: 180,
    durationMs: 2000,
    fps: 10,
    hasVideo: path.endsWith('.mp4'),
    hasAudio: true,
  );
  @override
  Future<int> frames(String path, String out, double fps, int maxSide) async {
    await Directory(out).create(recursive: true);
    for (var i = 0; i < 20; i++) {
      final png = img.encodePng(img.Image(width: 8, height: 8));
      await File('$out/${'$i'.padLeft(5, '0')}.jpg').writeAsBytes(png);
    }
    return 20;
  }

  @override
  Future<bool> audio(String path, String out) async {
    await File(out).writeAsBytes(encodeWav(level(1000, seconds: 2)));
    return true;
  }
}

class FakeOut extends AudioOut {
  final played = <(String, Duration, Duration?)>[];
  var stops = 0;
  Duration? at;
  @override
  Future<Duration?> position() async => at;
  @override
  Future<void> play(String path, Duration from, {Duration? length}) async =>
      played.add((path, from, length));
  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> release() async {}
}

void main() {
  test('WAV in and out; the mix adds sounds at their places and volumes', () {
    final wav = encodeWav(level(123));
    expect(decodeWav(wav).take(4), [123, 123, 123, 123]);
    expect(() => decodeWav(Uint8List(20)), throwsFormatException);

    final mix = mixAudio(
      [
        (
          samples: level(1000),
          start: 2,
          length: 4,
          sourceIn: 0,
          volume: const [],
        ),
        (
          samples: level(30000),
          start: 4,
          length: 4,
          sourceIn: 1,
          volume: const [Keyframe(0, .5)],
        ),
      ],
      10,
      10,
    );
    int at(int frame) => mix[(frame * audioRate ~/ 10 + 10) * 2];
    expect([at(0), at(2), at(4), at(6), at(8)], [0, 1000, 16000, 15000, 0]);
    final loud = mixAudio(
      [
        for (var i = 0; i < 3; i++)
          (
            samples: level(20000),
            start: 0,
            length: 2,
            sourceIn: 0,
            volume: const <Keyframe>[],
          ),
      ],
      2,
      10,
    );
    expect(loud[100], 32767, reason: 'clipped, not wrapped');
    expect(wavePeaks(Int16List.fromList([0, 0, 16384, -32768]), 1), [0, 1]);
  });

  test('pictures: one layer, or a frame each with its own time', () {
    final still = img.encodePng(img.Image(width: 100, height: 50));
    final drawing = decodePicture(still);
    expect((drawing.size.width, drawing.layers.length), (100, 1));
    final anim = img.Image(width: 8, height: 8)
      ..frameDuration = 100
      ..addFrame(img.Image(width: 8, height: 8)..frameDuration = 300);
    final gif = img.encodeGif(anim);
    expect(decodePicture(gif).layers, hasLength(2));
    expect(gifDurations(gif), [100, 300]);
  });

  test('PDF pages drawn by the platform become a layer each', () {
    final page = img.Image(width: 300, height: 200);
    img.fill(page, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(
      page,
      x1: 50,
      y1: 50,
      x2: 250,
      y2: 150,
      color: img.ColorRgb8(255, 0, 0),
    );
    final drawing = pdfPagesDrawing([img.encodePng(page), img.encodePng(page)]);
    expect([for (final l in drawing.layers) l.name], ['Page 1', 'Page 2']);
    expect((drawing.size.width, drawing.size.height), (300, 200));
    final i = (100 * 300 + 150) * 4;
    expect(drawing.layers.first.rgba.sublist(i, i + 4), [255, 0, 0, 255]);
    expect(() => pdfPagesDrawing([Uint8List(4)]), throwsFormatException);
  });

  testWidgets('a GIF comes in as a Flipbook; a video with its pictures and '
      'sound; its sound separates; playing mixes and plays it', (tester) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('media'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));
    final storage = MemoryStorage();
    final c = MovieController(
      storage: storage,
      movie: MovieDocument(
        id: 'm',
        name: 'M',
        width: 320,
        height: 180,
        fps: 10,
        frames: 60,
      ),
    );
    addTearDown(c.dispose);
    c.media = MediaCache(
      storage,
      tools: FakeTools(dir),
      folder: () async => dir,
    );
    final out = FakeOut();
    c.audio = out;

    final anim = img.Image(width: 8, height: 8)
      ..frameDuration = 300
      ..addFrame(img.Image(width: 8, height: 8)..frameDuration = 100);
    await tester.runAsync(() => c.importPicture(img.encodeGif(anim), 'Wave'));
    final flip = c.movie.tracks.single.contents.single;
    expect((flip.kind, flip.length), (TrackKind.flipbook, 4));
    final doc = c.drawings[flip.id]!;
    expect(doc.animation!.hold(ArtDocument.frameId(doc.pages.first)), 2);

    c.seek(5);
    await tester.runAsync(() async {
      expect(await c.importMedia('${dir.path}/clip.mp4', 'Clip'), isTrue);
      await c.media.frames('media0');
      await c.media.sound('media0');
    });
    final video = c.movie.tracks.first.contents.single;
    expect(
      (video.kind, video.start, video.length, video.sourceLength),
      (TrackKind.video, 5, 20, 20),
    );
    expect(c.media.framePath('media0', 1.25), endsWith('00012.jpg'));
    expect(c.media.peaks['media0'], isNotEmpty);
    expect(await tester.runAsync(() => c.importMedia('x.txt', 'X')), isFalse);

    c.separateAudio(video.id, 'Sound');
    expect(c.movie.tracks.first.kind, TrackKind.audio, reason: 'just above it');
    expect(c.movie.tracks[1].contents.single.id, video.id);
    expect(c.content(video.id)!.muted, isTrue);
    final sound = c.movie.tracks.first.contents.single;
    expect((sound.start, sound.length, sound.mediaId), (5, 20, 'media0'));

    c.seek(10);
    await tester.runAsync(() async {
      c.play();
      for (var i = 0; i < 100 && out.played.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    // The sound says it is 2 s in: the playhead follows it there.
    out.at = const Duration(seconds: 2);
    await tester.runAsync(() async {
      for (var i = 0; i < 50 && c.playhead.value < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    expect(c.playhead.value, inInclusiveRange(30, 31), reason: '10 + 2 s');
    // A clock that stands still is not followed.
    final there = c.playhead.value;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    expect(c.playhead.value, greaterThan(there), reason: 'the timer goes on');
    c.stop();
    expect(out.played.single.$2, const Duration(seconds: 1));
    expect(out.stops, 1);
    final mixed = decodeWav(
      (await tester.runAsync(() => File(out.played.single.$1).readAsBytes()))!,
    );
    int at(int frame) => mixed[(frame * audioRate ~/ 10 + 5) * 2];
    expect([at(2), at(8)], [0, 1000], reason: 'one sound: the video is quiet');
  });
}
