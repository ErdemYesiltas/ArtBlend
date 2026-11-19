import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../domain/keyframes.dart';

/// Movie sound is 48 kHz stereo 16-bit everywhere.
const audioRate = 48000;

/// What a media file holds.
class MediaInfo {
  const MediaInfo({
    required this.width,
    required this.height,
    required this.durationMs,
    required this.fps,
    required this.hasVideo,
    required this.hasAudio,
  });
  final int width, height, durationMs;
  final double fps;
  final bool hasVideo, hasAudio;

  static MediaInfo? fromMap(Object? map) => map is Map
      ? MediaInfo(
          width: (map['width'] as num?)?.toInt() ?? 0,
          height: (map['height'] as num?)?.toInt() ?? 0,
          durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
          fps: (map['fps'] as num?)?.toDouble() ?? 30,
          hasVideo: map['hasVideo'] == true,
          hasAudio: map['hasAudio'] == true,
        )
      : null;
}

/// The platform's media reading (Android MediaCodec, macOS AVFoundation).
class MediaTools {
  const MediaTools();
  static const _channel = MethodChannel('artblend/media');

  Future<MediaInfo?> probe(String path) async =>
      MediaInfo.fromMap(await _channel.invokeMethod('probe', {'path': path}));

  /// Pictures [fps] a second as `out/00000.jpg` …, at most [maxSide] px;
  /// how many.
  Future<int> frames(String path, String out, double fps, int maxSide) async =>
      await _channel.invokeMethod<int>('frames', {
        'path': path,
        'out': out,
        'fps': fps,
        'maxSide': maxSide,
      }) ??
      0;

  /// A PDF's pages drawn by the platform (vectors too), on white, at most
  /// [maxSide] pixels; the PNG files, a page each.
  Future<List<String>> pdfPages(String path, String out, int maxSide) async =>
      (await _channel.invokeListMethod<String>('pdfPages', {
        'path': path,
        'out': out,
        'maxSide': maxSide,
      })) ??
      const [];

  /// The sound decoded to a [audioRate] stereo WAV at [out].
  Future<bool> audio(String path, String out) async =>
      await _channel.invokeMethod<bool>('audio', {'path': path, 'out': out}) ??
      false;
}

/// Plays a WAV from a point (the movie's mixed sound), or a sliver of it
/// (scrubbing).
class AudioOut {
  const AudioOut();
  static const _channel = MethodChannel('artblend/audio');

  Future<void> play(String path, Duration from, {Duration? length}) =>
      _channel.invokeMethod('play', {
        'path': path,
        'offsetMs': from.inMilliseconds,
        'lengthMs': ?length?.inMilliseconds,
      });

  Future<void> stop() => _channel.invokeMethod('stop');

  /// Where the sound is now, while it plays.
  Future<Duration?> position() async =>
      switch (await _channel.invokeMethod<int>('position')) {
        final ms? => Duration(milliseconds: ms),
        null => null,
      };
  Future<void> release() => _channel.invokeMethod('release');
}

/// Interleaved stereo 16-bit samples as a WAV file.
Uint8List encodeWav(Int16List samples) {
  final data = samples.lengthInBytes;
  final out = ByteData(44 + data);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      out.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  out.setUint32(4, 36 + data, Endian.little);
  ascii(8, 'WAVEfmt ');
  out
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 2, Endian.little)
    ..setUint32(24, audioRate, Endian.little)
    ..setUint32(28, audioRate * 4, Endian.little)
    ..setUint16(32, 4, Endian.little)
    ..setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  out.setUint32(40, data, Endian.little);
  final bytes = out.buffer.asUint8List();
  bytes.setRange(
    44,
    44 + data,
    samples.buffer.asUint8List(samples.offsetInBytes, data),
  );
  return bytes;
}

/// A WAV's interleaved stereo 16-bit samples (its "data" chunk); throws
/// [FormatException] for anything else.
Int16List decodeWav(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  String tag(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));
  if (bytes.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw const FormatException('Not a WAV');
  }
  var at = 12;
  while (at + 8 <= bytes.length) {
    final size = data.getUint32(at + 4, Endian.little);
    if (tag(at) == 'data') {
      final end = math.min(bytes.length, at + 8 + size);
      final copy = Uint8List.fromList(
        bytes.sublist(at + 8, end - (end - at - 8) % 2),
      );
      return copy.buffer.asInt16List();
    }
    at += 8 + size + size % 2;
  }
  throw const FormatException('WAV without data');
}

/// One sound in the movie's mix: its samples, where it starts and stops
/// (movie frames), from which source frame, and its volume keyframes
/// (frames from its start; none: full).
typedef MixPart = ({
  Int16List samples,
  int start,
  int length,
  int sourceIn,
  Keys volume,
});

/// The movie's [frames] at [fps] of sound: [parts] added together, each at
/// its volume (eased between keyframes), clipped to 16 bits.
Int16List mixAudio(List<MixPart> parts, int frames, int fps) {
  final perFrame = audioRate / fps;
  final total = (frames * perFrame).round();
  final sum = Float64List(total * 2);
  for (final p in parts) {
    final from = (p.start * perFrame).round();
    final to = math.min(total, ((p.start + p.length) * perFrame).round());
    final skip = (p.sourceIn * perFrame).round();
    var frame = -1;
    var gain = 1.0;
    for (var i = from; i < to; i++) {
      final source = (skip + i - from) * 2;
      if (source + 1 >= p.samples.length) break;
      final f = (i / perFrame).floor() - p.start;
      if (f != frame) {
        frame = f;
        gain = keyValue(p.volume, f) ?? 1;
      }
      sum[i * 2] += p.samples[source] * gain;
      sum[i * 2 + 1] += p.samples[source + 1] * gain;
    }
  }
  return Int16List.fromList([
    for (final v in sum) v.round().clamp(-32768, 32767),
  ]);
}

/// Loudest sample (0–1) in each run of [bucket] stereo samples: a
/// waveform to draw.
Float32List wavePeaks(Int16List samples, int bucket) {
  final count = (samples.length / 2 / bucket).ceil();
  final peaks = Float32List(count);
  for (var i = 0; i < samples.length; i++) {
    final b = i ~/ 2 ~/ bucket;
    final v = samples[i].abs() / 32768;
    if (v > peaks[b]) peaks[b] = v;
  }
  return peaks;
}
