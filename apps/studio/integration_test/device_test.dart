import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/data/export_formats.dart';
import 'package:atelier_studio/data/media.dart';
import 'package:atelier_studio/data/timelapse.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/drawing/native_stroke.dart';
import 'package:atelier_studio/editor/exporter.dart';
import 'package:atelier_studio/movie/movie_export.dart';
import 'package:atelier_studio/movie/movie_controller.dart';
import 'package:atelier_studio/domain/movie.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/memory_storage.dart';

/// Checks only a real device can make: the GPU, the native brush engine,
/// the platform video encoder. Nothing here touches the app's drawings
/// (memory storage, temporary files only).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a native stamp stroke renders on the device', (tester) async {
    final brush = initialBrushes.firstWhere((b) => b.id == 'stamp-graphite');
    final image = await tester.runAsync(() => renderNativePreview(brush));
    final data = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.rawStraightRgba),
    );
    final rgba = data!.buffer.asUint8List();
    var painted = 0;
    for (var i = 3; i < rgba.length; i += 4) {
      if (rgba[i] > 32) painted++;
    }
    expect(painted, greaterThan(200));
  });

  testWidgets('the time-lapse encoder writes a playable MP4', (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory(
        '${(await getTemporaryDirectory()).path}/it-timelapse',
      ).create(recursive: true);
      try {
        final frames = <String>[];
        for (var i = 0; i < 45; i++) {
          final rgba = Uint8List(320 * 240 * 4);
          for (var p = 0; p < 320 * 240; p++) {
            final x = p % 320;
            rgba.setAll(p * 4, [
              x < i * 7 ? 220 : 30,
              60,
              x < i * 7 ? 40 : 200,
              255,
            ]);
          }
          final file = File('${dir.path}/${TimelapseStore.frameName(i)}');
          await file.writeAsBytes(encodeJpeg(RgbaPixels(320, 240, rgba)));
          frames.add(file.path);
        }
        final output = '${dir.path}/out.mp4';
        final ok = await const VideoEncoder().encode(
          frames: frames,
          output: output,
          width: 320,
          height: 240,
        );
        expect(ok, isTrue);
        final bytes = await File(output).readAsBytes();
        expect(bytes.length, greaterThan(2000));
        expect(String.fromCharCodes(bytes.sublist(4, 8)), 'ftyp');
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  testWidgets('a drawing exports to PSD and PNG on the device', (tester) async {
    await tester.runAsync(() async {
      final c = StudioController(storage: MemoryStorage());
      await c.initialize();
      await c.replaceDocument(
        ArtDocument.empty(name: 'IT', dimensions: const CanvasSize(256, 256)),
      );
      c.setSelection(
        SelectionRegion.rectangle(const ui.Rect.fromLTWH(0, 0, 128, 256)),
      );
      await c.fillActiveLayer();
      final psd = await Exporter(c).export(ExportFormat.psd);
      expect(String.fromCharCodes(psd.sublist(0, 4)), '8BPS');
      final png = await Exporter(c).export(ExportFormat.png);
      expect(png.sublist(1, 4), [0x50, 0x4e, 0x47]);
      c.dispose();
    });
  });

  testWidgets('an animation exports to MP4 and GIF on the device', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final c = StudioController(storage: MemoryStorage());
      await c.initialize();
      await c.replaceDocument(
        ArtDocument(
          id: 'it-anim',
          name: 'IT',
          dimensions: const CanvasSize(320, 240),
          layers: [
            for (var i = 0; i < 4; i++) ArtLayer(id: 'f$i', name: 'F$i'),
          ],
          activeLayerId: 'f0',
        ),
      );
      for (var i = 0; i < 4; i++) {
        c.selectLayer('f$i');
        c.setSelection(
          SelectionRegion.rectangle(ui.Rect.fromLTWH(i * 80.0, 0, 80, 240)),
        );
        await c.fillActiveLayer();
      }
      c.setSelection(null);
      c.setAnimationAssist(true);
      final mp4 = await Exporter(c).export(ExportFormat.mp4);
      expect(String.fromCharCodes(mp4.sublist(4, 8)), 'ftyp');
      final gif = await Exporter(c).export(ExportFormat.gif, web: true);
      expect(String.fromCharCodes(gif.sublist(0, 6)), 'GIF89a');
      c.dispose();
    });
  });

  testWidgets('movie media: a video probed and cut into proxy pictures, a '
      'sound decoded to 48 kHz WAV, played and stopped', (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory(
        '${(await getTemporaryDirectory()).path}/it-media',
      ).create(recursive: true);
      try {
        final frames = <String>[];
        for (var i = 0; i < 24; i++) {
          final rgba = Uint8List(160 * 120 * 4);
          for (var p = 0; p < 160 * 120; p++) {
            rgba.setAll(p * 4, [p % 160 < i * 6 ? 230 : 20, 90, 40, 255]);
          }
          final file = File('${dir.path}/${TimelapseStore.frameName(i)}');
          await file.writeAsBytes(encodeJpeg(RgbaPixels(160, 120, rgba)));
          frames.add(file.path);
        }
        final video = '${dir.path}/clip.mp4';
        expect(
          await const VideoEncoder().encode(
            frames: frames,
            output: video,
            width: 160,
            height: 120,
            fps: 12,
          ),
          isTrue,
        );
        const tools = MediaTools();
        final info = (await tools.probe(video))!;
        expect((info.width, info.height, info.hasVideo), (160, 120, true));
        expect(info.durationMs, inInclusiveRange(1800, 2200));
        final count = await tools.frames(video, '${dir.path}/proxy', 12, 80);
        expect(count, greaterThanOrEqualTo(20));
        expect(File('${dir.path}/proxy/00010.jpg').existsSync(), isTrue);

        final tone = Int16List(audioRate * 2);
        for (var i = 0; i < audioRate; i++) {
          final v = (math.sin(i / 20) * 8000).round();
          tone[i * 2] = v;
          tone[i * 2 + 1] = v;
        }
        final source = File('${dir.path}/tone.wav');
        await source.writeAsBytes(encodeWav(tone));
        final out = '${dir.path}/decoded.wav';
        expect(await tools.audio(source.path, out), isTrue);
        final decoded = decodeWav(await File(out).readAsBytes());
        expect(decoded.length, closeTo(tone.length, audioRate ~/ 10));
        const speaker = AudioOut();
        await speaker.play(out, Duration.zero);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final at = await speaker.position();
        expect(at, isNotNull, reason: 'the sound clock while it plays');
        expect(at!.inMilliseconds, inInclusiveRange(50, 1000));
        await speaker.stop();
        await speaker.release();

        // PDF pages drawn by the platform.
        final pdfFile = File('${dir.path}/doc.pdf');
        final grey = RgbaPixels(
          160,
          120,
          Uint8List(160 * 120 * 4)..fillRange(0, 160 * 120 * 4, 200),
        );
        await pdfFile.writeAsBytes(
          encodePdf([
            for (var i = 0; i < 2; i++) PdfPage(encodeJpeg(grey), 160, 120, 72),
          ], title: 'IT'),
        );
        final pages = await tools.pdfPages(
          pdfFile.path,
          '${dir.path}/pages',
          400,
        );
        expect(pages, hasLength(2));
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  testWidgets('a movie exports to MP4 with its sound track', (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory(
        '${(await getTemporaryDirectory()).path}/it-movie',
      ).create(recursive: true);
      try {
        final tone = Int16List(audioRate * 2);
        for (var i = 0; i < audioRate; i++) {
          tone[i * 2] = tone[i * 2 + 1] = (math.sin(i / 30) * 6000).round();
        }
        final wav = File('${dir.path}/tone.wav')
          ..writeAsBytesSync(encodeWav(tone));
        final storage = MemoryStorage();
        final soundId = await storage.importMedia(wav.path);
        final c = MovieController(
          storage: storage,
          movie: MovieDocument(
            id: 'it',
            name: 'IT',
            width: 160,
            height: 120,
            fps: 12,
            frames: 12,
            background: 0xff2040a0,
            tracks: [
              MovieTrack(
                id: 's',
                name: 'Sound',
                kind: TrackKind.audio,
                contents: [
                  MovieContent(
                    id: 'snd',
                    name: 'Tone',
                    kind: TrackKind.audio,
                    start: 0,
                    length: 12,
                    sourceLength: 12,
                    mediaId: soundId,
                  ),
                ],
              ),
            ],
          ),
        );
        await c.media.sound(soundId);
        final mp4 = await MovieExporter(c)
            .export(const MovieExportOptions(MovieFormat.mp4));
        final out = File('${dir.path}/movie.mp4')..writeAsBytesSync(mp4);
        final info = (await const MediaTools().probe(out.path))!;
        expect((info.hasVideo, info.hasAudio), (true, true));
        c.dispose();
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
