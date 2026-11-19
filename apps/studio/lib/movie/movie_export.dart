import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../data/export_formats.dart';
import '../data/studio_storage.dart';
import '../data/timelapse.dart';
import '../domain/document.dart';
import '../domain/movie.dart';
import 'drawing_frames.dart';
import 'media_cache.dart';
import 'movie_controller.dart';
import 'stage.dart';

/// What a movie can be exported as (Dreams' Share).
enum MovieFormat {
  mp4('mp4', 'video/mp4'),
  hevc('mov', 'video/quicktime'),
  gif('gif', 'image/gif'),
  png('zip', 'application/zip'),
  jpeg('zip', 'application/zip'),
  tiff('zip', 'application/zip'),
  tga('zip', 'application/zip'),
  bmp('zip', 'application/zip'),
  frame('png', 'image/png'),
  project('artmovie', 'application/zip');

  const MovieFormat(this.extension, this.mimeType);
  final String extension, mimeType;

  bool get sequence => index >= png.index && index <= bmp.index;
}

/// How an export is made: [preview] at half size; GIF's palette, dither
/// and the alpha below which a transparent movie's pixels are left out.
class MovieExportOptions {
  const MovieExportOptions(
    this.format, {
    this.preview = false,
    this.gifColors = 256,
    this.gifDither = true,
    this.alphaThreshold = .5,
  });
  final MovieFormat format;
  final bool preview;
  final int gifColors;
  final bool gifDither;
  final double alphaThreshold;
}

Uint8List _png(RgbaPixels p) => encodePngPixels(p);
Uint8List _jpeg((RgbaPixels, int) job) =>
    encodeJpeg(job.$1, quality: 95, background: job.$2);
Uint8List _tiff(RgbaPixels p) => encodeTiff(p);
img.Image _picture(RgbaPixels p) => img.Image.fromBytes(
  width: p.width,
  height: p.height,
  bytes: p.bytes.buffer,
  bytesOffset: p.bytes.offsetInBytes,
  numChannels: 4,
);
Uint8List _tga(RgbaPixels p) => img.encodeTga(_picture(p));
Uint8List _bmp(RgbaPixels p) => img.encodeBmp(_picture(p));
Uint8List _gif((List<TimedFrame>, bool, int, int, bool, double?) job) =>
    encodeGif(
      job.$1,
      loop: job.$2,
      background: job.$3,
      colors: job.$4,
      dither: job.$5,
      alphaThreshold: job.$6,
    );

/// Renders a movie frame by frame, as it will be in a file, and encodes it.
class MovieExporter {
  MovieExporter(this.c);
  final MovieController c;

  MovieDocument get movie => c.movie;

  /// The export's size: the movie's, halved for a preview, even sides
  /// (video encoders want them).
  (int, int) size({bool preview = false}) {
    int even(double v) => math.max(2, (v / 2).floor() * 2);
    final scale = preview ? .5 : 1.0;
    return (even(movie.width * scale), even(movie.height * scale));
  }

  /// Frame [frame] as pixels, every picture it needs loaded first.
  Future<RgbaPixels> renderFrame(
    int frame,
    int width,
    int height, {
    required DrawingFrames cache,
    required String? Function(String id, double seconds) proxy,
  }) async {
    for (var round = 0; ; round++) {
      final recorder = ui.PictureRecorder();
      paintMovieFrame(
        ui.Canvas(recorder),
        ui.Size(width.toDouble(), height.toDouble()),
        c,
        frame,
        cache: cache,
        proxy: proxy,
      );
      final picture = recorder.endRecording();
      if (cache.busy && round < 400) {
        picture.dispose();
        while (cache.busy) {
          await Future<void>.delayed(const Duration(milliseconds: 8));
        }
        continue;
      }
      final image = await picture.toImage(width, height);
      picture.dispose();
      final data = await image.toByteData();
      image.dispose();
      return RgbaPixels(
        width,
        height,
        data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    }
  }

  /// [options] made into a file's bytes; [progress] hears 0–1 along the way.
  Future<Uint8List> export(
    MovieExportOptions options, {
    void Function(double done)? progress,
  }) async {
    if (options.format == MovieFormat.project) return encodeProject();
    if (c.shaders == null) await c.loadShaders();
    final (width, height) = size(preview: options.preview);
    final cache = DrawingFrames(longest: math.max(width, height) * 1.0);
    final proxies = <String, Proxies>{};
    for (final t in movie.tracks) {
      for (final x in t.contents) {
        if (x.kind == TrackKind.video && x.mediaId != null) {
          final p = await c.media.framesAt(
            x.mediaId!,
            movie.fps.toDouble(),
            math.max(width, height),
          );
          if (p != null) proxies[x.mediaId!] = p;
        }
      }
    }
    String? proxy(String id, double seconds) => switch (proxies[id]) {
      final p? => MediaCache.framePathIn(p, seconds),
      null => c.media.framePath(id, seconds),
    };
    Future<RgbaPixels> render(int f) =>
        renderFrame(f, width, height, cache: cache, proxy: proxy);
    final background = movie.transparent ? 0xff000000 : movie.background;
    try {
      switch (options.format) {
        case MovieFormat.frame:
          return await compute(_png, await render(c.playhead.value));
        case MovieFormat.gif:
          final frames = <TimedFrame>[];
          for (var f = 0; f < movie.frames; f++) {
            frames.add((pixels: await render(f), ms: 1000 ~/ movie.fps));
            progress?.call(f / movie.frames * .8);
          }
          return await compute(_gif, (
            frames,
            movie.playback != PlaybackMode.oneShot,
            movie.transparent ? 0xffffffff : movie.background,
            options.gifColors,
            options.gifDither,
            movie.transparent ? options.alphaThreshold : null,
          ));
        case MovieFormat.mp4 || MovieFormat.hevc:
          return await _video(
            render,
            width,
            height,
            alpha: options.format == MovieFormat.hevc,
            background: background,
            progress: progress,
          );
        case _ when options.format.sequence:
          final archive = Archive();
          final ext = options.format.name == 'jpeg'
              ? 'jpg'
              : options.format.name;
          for (var f = 0; f < movie.frames; f++) {
            final pixels = await render(f);
            final bytes = await switch (options.format) {
              MovieFormat.jpeg => compute(_jpeg, (pixels, background)),
              MovieFormat.tiff => compute(_tiff, pixels),
              MovieFormat.tga => compute(_tga, pixels),
              MovieFormat.bmp => compute(_bmp, pixels),
              _ => compute(_png, pixels),
            };
            archive.addFile(
              ArchiveFile.bytes('${'${f + 1}'.padLeft(5, '0')}.$ext', bytes),
            );
            progress?.call(f / movie.frames);
          }
          return Uint8List.fromList(ZipEncoder().encode(archive));
        case _:
          throw StateError('Not a movie export: ${options.format}');
      }
    } finally {
      cache.dispose();
    }
  }

  Future<Uint8List> _video(
    Future<RgbaPixels> Function(int frame) render,
    int width,
    int height, {
    required bool alpha,
    required int background,
    void Function(double done)? progress,
  }) async {
    final dir = await Directory(
      '${(await c.media.folder()).path}/artblend-export-${newId()}',
    ).create(recursive: true);
    try {
      final paths = <String>[];
      for (var f = 0; f < movie.frames; f++) {
        final pixels = await render(f);
        final file = File('${dir.path}/$f.${alpha ? 'png' : 'jpg'}');
        await file.writeAsBytes(
          alpha
              ? await compute(_png, pixels)
              : await compute(_jpeg, (pixels, background)),
        );
        paths.add(file.path);
        progress?.call(f / movie.frames * .9);
      }
      final out = '${dir.path}/movie.${alpha ? 'mov' : 'mp4'}';
      final ok = await const VideoEncoder().encode(
        frames: paths,
        output: out,
        width: width,
        height: height,
        fps: movie.fps,
        alpha: alpha,
        audio: await c.soundMix(),
      );
      if (!ok) throw StateError('The video could not be made');
      return await File(out).readAsBytes();
    } finally {
      await dir.delete(recursive: true);
    }
  }

  /// The whole movie as one file: its settings and tracks, every drawing
  /// with its tiles, every media file.
  Future<Uint8List> encodeProject() async {
    final used = {
      for (final t in movie.tracks)
        for (final x in t.contents) x.id,
    };
    final drawings = {
      for (final MapEntry(:key, :value) in c.drawings.entries)
        if (used.contains(key)) key: value,
    };
    await RasterAsset.hashAll([
      for (final d in drawings.values)
        for (final l in d.layers) ...?l.raster?.tiles.values,
    ]);
    final blobs = <String, Uint8List>{};
    final manifests = {
      for (final MapEntry(:key, :value) in drawings.entries)
        key: value.toJson(blobs: blobs),
    };
    final archive = Archive()
      ..addFile(
        ArchiveFile.bytes(
          'movie.json',
          utf8.encode(
            jsonEncode({
              'format': 'artblend.movie-package',
              'version': 1,
              'movie': movie.toJson(),
              'drawings': manifests,
            }),
          ),
        ),
      );
    for (final MapEntry(:key, :value) in blobs.entries) {
      archive.addFile(ArchiveFile.bytes('tiles/$key.png', value));
    }
    final media = {
      for (final t in movie.tracks)
        for (final x in t.contents) ?x.mediaId,
    };
    for (final id in media) {
      final path = await c.storage.mediaPath(id);
      if (path != null) {
        archive.addFile(
          ArchiveFile.bytes('media/$id', await File(path).readAsBytes()),
        );
      }
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}

/// An `.artmovie` file brought into [storage] as a new movie (its media
/// copied in, new ids); the movie, or null when it is not one.
Future<MovieDocument?> importProject(
  Uint8List bytes,
  StudioStorage storage,
  Directory scratch,
) async {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return null;
  }
  final manifest = archive.findFile('movie.json');
  if (manifest == null) return null;
  final json = jsonDecode(utf8.decode(manifest.content));
  if (json is! Map || json['format'] != 'artblend.movie-package') return null;
  var movieJson = Map<String, dynamic>.from(json['movie'] as Map);
  // Media come in under new ids.
  final renamed = <String, String>{};
  for (final file in archive.files) {
    if (!file.isFile || !file.name.startsWith('media/')) continue;
    final old = file.name.substring('media/'.length);
    final temp = File('${scratch.path}/import-${newId()}-$old');
    await temp.writeAsBytes(file.content);
    renamed[old] = await storage.importMedia(temp.path);
    await temp.delete();
  }
  Object? remap(Object? v) => switch (v) {
    {'mediaId': final String id} && final Map m => {
      for (final MapEntry(:key, :value) in m.entries)
        key: key == 'mediaId' ? renamed[id] ?? id : remap(value),
    },
    final Map m => {
      for (final MapEntry(:key, :value) in m.entries) key: remap(value),
    },
    final List l => [for (final e in l) remap(e)],
    _ => v,
  };
  movieJson = Map<String, dynamic>.from(remap(movieJson) as Map);
  final movie = MovieDocument.fromJson(movieJson).copyWith(id: newId());
  final drawings = <String, ArtDocument>{};
  if (json['drawings'] case final Map manifests) {
    for (final MapEntry(:key, :value) in manifests.entries) {
      final doc = Map<String, dynamic>.from(value as Map);
      final blobs = <String, Uint8List>{
        for (final digest in referencedBlobs(doc))
          if (archive.findFile('tiles/$digest.png') case final tile?)
            digest: Uint8List.fromList(tile.content),
      };
      drawings[key as String] = ArtDocument.fromJson(
        doc,
        blobs: verifiedBlobs(blobs),
      );
    }
  }
  await storage.saveMovie(movie, drawings: drawings);
  return movie;
}
