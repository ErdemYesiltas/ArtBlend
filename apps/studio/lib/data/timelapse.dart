import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// A drawing's time-lapse frames on disk: one JPEG per change, all the
/// same size (the first frame's), numbered in order.
class TimelapseStore {
  TimelapseStore(this.root);
  final Directory root;

  static Future<TimelapseStore> open() async => TimelapseStore(
    Directory('${(await getApplicationSupportDirectory()).path}/timelapse'),
  );

  Directory folder(String documentId) =>
      Directory('${root.path}/${base64Url.encode(utf8.encode(documentId))}');

  File _meta(String documentId) => File('${folder(documentId).path}/meta.json');

  static String frameName(int index) =>
      '${index.toString().padLeft(6, '0')}.jpg';

  /// The video size, once the first frame set it.
  Future<(int, int)?> size(String documentId) async {
    final file = _meta(documentId);
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      return (json['width'] as int, json['height'] as int);
    } on Object {
      return null;
    }
  }

  Future<void> setSize(String documentId, int width, int height) async {
    await folder(documentId).create(recursive: true);
    await _meta(documentId)
        .writeAsString(jsonEncode({'width': width, 'height': height}));
  }

  /// The frames, first to last.
  Future<List<File>> frames(String documentId) async {
    final dir = folder(documentId);
    if (!await dir.exists()) return const [];
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.jpg'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<void> add(String documentId, int index, Uint8List jpeg) async {
    final dir = folder(documentId);
    await dir.create(recursive: true);
    final file = File('${dir.path}/${frameName(index)}');
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(jpeg, flush: true);
    await temp.rename(file.path);
  }

  Future<void> delete(String documentId) async {
    final dir = folder(documentId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

/// The time-lapse video size for a [width]×[height] drawing: its shape,
/// the longer side at most [longest], both sides even (as encoders need).
(int, int) timelapseSize(int width, int height, {int longest = 1080}) {
  final scale = math.min(1.0, longest / math.max(width, height));
  int even(double v) => math.max(2, (v / 2).round() * 2);
  return (even(width * scale), even(height * scale));
}

/// The frames a video of at most [seconds] at [fps] shows: all of them, or
/// evenly spread ones with the first and the last kept.
List<T> framesFor<T>(List<T> frames, {int? seconds, int fps = 30}) {
  if (seconds == null) return frames;
  final most = seconds * fps;
  if (frames.length <= most) return frames;
  return [
    for (var i = 0; i < most; i++)
      frames[(i * (frames.length - 1) / (most - 1)).round()],
  ];
}

/// Encodes JPEG frames into an H.264 MP4 with the platform's own encoder
/// (MediaCodec on Android, AVFoundation on macOS).
class VideoEncoder {
  const VideoEncoder();
  static const _channel = MethodChannel('artblend/video');

  /// [frames] (paths, in order) into [output]; true when it was written.
  /// [alpha] (macOS): HEVC with transparency in a QuickTime file. [audio]
  /// (a WAV) goes in as an AAC sound track.
  Future<bool> encode({
    required List<String> frames,
    required String output,
    required int width,
    required int height,
    int fps = 30,
    bool alpha = false,
    String? audio,
  }) async =>
      await _channel.invokeMethod<bool>('encode', {
        'frames': frames,
        'output': output,
        'width': width,
        'height': height,
        'fps': fps,
        'alpha': alpha,
        'audio': ?audio,
      }) ??
      false;
}
