import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/media.dart';
import '../data/studio_storage.dart';

Float32List _peaks(Int16List samples) =>
    wavePeaks(samples, audioRate ~/ MediaCache.peaksPerSecond);

/// A video's pictures as small JPEGs, [fps] a second.
typedef Proxies = ({String dir, int count, double fps});

/// Each media file's pictures and sound made ready once (kept in the
/// temporary folder, rebuilt when it is gone): what the stage shows, the
/// timeline draws and playback mixes.
class MediaCache extends ChangeNotifier {
  MediaCache(
    this.storage, {
    this.tools = const MediaTools(),
    Future<Directory> Function()? folder,
  }) : _folder = folder ?? getTemporaryDirectory;

  final StudioStorage storage;
  final MediaTools tools;
  final Future<Directory> Function() _folder;

  final _info = <String, Future<MediaInfo?>>{};
  final _frames = <String, Future<Proxies?>>{};
  final _framesAt = <String, Future<Proxies?>>{};
  final _sound = <String, Future<Int16List?>>{};

  /// What is ready, by media id.
  final proxies = <String, Proxies>{};
  final sounds = <String, Int16List>{};

  /// Each sound's loudness, 100 a second.
  final peaks = <String, Float32List>{};

  bool _disposed = false;

  static const peaksPerSecond = 100;

  /// Where made-ready media (and the movie's mixed sound) are kept.
  Future<Directory> folder() => _folder();

  Future<String> _dir(String id) async =>
      '${(await _folder()).path}/artblend-media/$id';

  Future<MediaInfo?> info(String id) => _info[id] ??= () async {
    final path = await storage.mediaPath(id);
    if (path == null) return null;
    try {
      return await tools.probe(path);
    } catch (_) {
      return null;
    }
  }();

  /// Pictures and sound of [id], made ready in the background.
  void prepare(String id) {
    frames(id);
    sound(id);
  }

  Future<Proxies?> frames(String id) => _frames[id] ??= () async {
    final media = await info(id);
    final path = await storage.mediaPath(id);
    if (media == null || !media.hasVideo || path == null) return null;
    final dir = '${await _dir(id)}/frames';
    final fps = math.min(media.fps, 30.0);
    final folder = Directory(dir);
    var count = await folder.exists()
        ? await folder.list().where((e) => e.path.endsWith('.jpg')).length
        : 0;
    if (count == 0) {
      try {
        count = await tools.frames(path, dir, fps, 640);
      } catch (_) {
        return null;
      }
    }
    if (count == 0 || _disposed) return null;
    final ready = (dir: dir, count: count, fps: fps);
    proxies[id] = ready;
    notifyListeners();
    return ready;
  }();

  Future<Int16List?> sound(String id) => _sound[id] ??= () async {
    final media = await info(id);
    final path = await storage.mediaPath(id);
    if (media == null || !media.hasAudio || path == null) return null;
    final wav = File('${await _dir(id)}/sound.wav');
    if (!await wav.exists()) {
      await wav.parent.create(recursive: true);
      try {
        if (!await tools.audio(path, wav.path)) return null;
      } catch (_) {
        return null;
      }
    }
    final bytes = await wav.readAsBytes();
    // Top-level functions: a closure here would carry `this` along.
    final samples = await compute(decodeWav, bytes);
    final loudness = await compute(_peaks, samples);
    if (_disposed) return null;
    sounds[id] = samples;
    peaks[id] = loudness;
    notifyListeners();
    return samples;
  }();

  /// The picture of video [id] at [seconds] into it, when made.
  String? framePath(String id, double seconds) {
    final p = proxies[id];
    return p == null ? null : framePathIn(p, seconds);
  }

  static String framePathIn(Proxies p, double seconds) {
    final i = (seconds * p.fps).floor().clamp(0, p.count - 1);
    return '${p.dir}/${'$i'.padLeft(5, '0')}.jpg';
  }

  /// Video [id]'s pictures at [fps] and up to [maxSide] pixels, for
  /// exporting (kept beside the stage's smaller ones).
  Future<Proxies?> framesAt(String id, double fps, int maxSide) =>
      _framesAt['$id@$fps@$maxSide'] ??= () async {
        final media = await info(id);
        final path = await storage.mediaPath(id);
        if (media == null || !media.hasVideo || path == null) return null;
        final dir = '${await _dir(id)}/frames-$maxSide-${fps.round()}';
        final folder = Directory(dir);
        var count = await folder.exists()
            ? await folder.list().where((e) => e.path.endsWith('.jpg')).length
            : 0;
        if (count == 0) {
          try {
            count = await tools.frames(path, dir, fps, maxSide);
          } catch (_) {
            return null;
          }
        }
        return count == 0 ? null : (dir: dir, count: count, fps: fps);
      }();

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
