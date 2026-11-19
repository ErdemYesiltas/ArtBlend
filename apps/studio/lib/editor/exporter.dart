import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import '../data/color_profiles.dart';
import '../data/export_formats.dart';
import '../data/timelapse.dart';
import '../domain/document.dart';
import '../drawing/brush_engine.dart';
import 'studio_controller.dart';

enum ExportFormat {
  png('png', 'image/png'),
  jpeg('jpg', 'image/jpeg'),
  tiff('tiff', 'image/tiff'),
  psd('psd', 'image/vnd.adobe.photoshop'),
  pdf('pdf', 'application/pdf'),
  layersPng('zip', 'application/zip'),
  layersPdf('pdf', 'application/pdf'),
  pagesPdf('pdf', 'application/pdf'),
  gif('gif', 'image/gif'),
  apng('png', 'image/apng'),
  mp4('mp4', 'video/mp4'),
  hevc('mov', 'video/quicktime');

  bool get animated => index >= gif.index;

  const ExportFormat(this.extension, this.mimeType);
  final String extension, mimeType;
}

/// Renders the open drawing (or its layers) and encodes it as [format];
/// the heavy encoding runs off the UI thread.
class Exporter {
  Exporter(this.controller);
  final StudioController controller;

  ArtDocument get _doc => controller.document;

  Future<RgbaPixels> _render(
    void Function(ui.Canvas canvas) paint, {
    (int, int)? size,
  }) async {
    final dimensions = _doc.dimensions;
    final (width, height) = size ?? (dimensions.width, dimensions.height);
    final recorder = ui.PictureRecorder();
    paint(
      ui.Canvas(recorder)
        ..scale(width / dimensions.width, height / dimensions.height),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    try {
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (data == null) throw StateError('Rendering failed');
      return RgbaPixels(
        width,
        height,
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  }

  Future<RgbaPixels> composite([ArtDocument? doc, (int, int)? size]) => _render(
    (canvas) => paintDocument(
      canvas,
      doc ?? _doc,
      FreehandBrushEngine(),
      rasterImages: controller.rasters.images,
    ),
    size: size,
  );

  /// Animation Assist's frames as one pass plays, each with its time on
  /// screen (holds included), at most [longest] pixels on the longest
  /// side (even sizes, for video).
  Future<List<TimedFrame>> animationFrames({int longest = 2048}) async {
    final doc = _doc, settings = doc.animation ?? const AnimationSettings();
    final size = timelapseSize(
      doc.dimensions.width,
      doc.dimensions.height,
      longest: longest,
    );
    final order = settings.playOrder([
      for (final p in doc.pages) ArtDocument.frameId(p),
    ]);
    final runs = <(int, int)>[];
    for (final i in order) {
      if (runs.isNotEmpty && runs.last.$1 == i) {
        runs.last = (i, runs.last.$2 + 1);
      } else {
        runs.add((i, 1));
      }
    }
    final rendered = <int, RgbaPixels>{};
    return [
      for (final (page, ticks) in runs)
        (
          pixels: rendered[page] ??= await composite(
            controller.animationFrame(page),
            size,
          ),
          ms: (ticks * 1000 / settings.fps).round(),
        ),
    ];
  }

  /// [frames] as a video at [fps] (each repeated for its time on screen),
  /// on the paper, or with [alpha] (HEVC, macOS) see-through.
  Future<Uint8List> _video(
    List<TimedFrame> frames,
    int fps, {
    required bool alpha,
    required int background,
  }) async {
    final dir = await Directory(
      '${(await getTemporaryDirectory()).path}/animation-${newId()}',
    ).create(recursive: true);
    try {
      final paths = <String>[];
      final written = <RgbaPixels, String>{};
      for (final (i, f) in frames.indexed) {
        final path = written[f.pixels] ??= await () async {
          final pixels = f.pixels;
          final file = File('${dir.path}/$i.${alpha ? 'png' : 'jpg'}');
          await file.writeAsBytes(
            await Isolate.run(
              () => alpha
                  ? encodePngPixels(pixels)
                  : encodeJpeg(pixels, quality: 95, background: background),
            ),
          );
          return file.path;
        }();
        final ticks = math.max(1, (f.ms * fps / 1000).round());
        paths.addAll(List.filled(ticks, path));
      }
      final first = frames.first.pixels;
      final output = '${dir.path}/out.${alpha ? 'mov' : 'mp4'}';
      final ok = await const VideoEncoder().encode(
        frames: paths,
        output: output,
        width: first.width,
        height: first.height,
        fps: fps,
        alpha: alpha,
      );
      if (!ok) throw StateError('The video could not be made');
      return await File(output).readAsBytes();
    } finally {
      await dir.delete(recursive: true);
    }
  }

  /// [layer]'s own pixels: mask applied, opacity and blend left to the
  /// file.
  Future<RgbaPixels> layerPixels(ArtLayer layer) => _render(
    (canvas) => paintLayer(
      canvas,
      layer,
      FreehandBrushEngine(),
      _doc.dimensions,
      rasterImages: controller.rasters.images,
      applyOpacity: false,
    ),
  );

  Future<RgbaPixels> _background() => _render(
    (canvas) => canvas.drawRect(
      _doc.dimensions.rect,
      ui.Paint()..color = ui.Color(_doc.background),
    ),
  );

  /// The drawing's colour space: CMYK drawings' RGB files are sRGB.
  bool get _cmyk => _doc.colorProfile == ColorProfile.cmyk;
  Uint8List? get _icc =>
      iccProfile(_cmyk ? ColorProfile.srgb : _doc.colorProfile);

  Future<Uint8List> layerPng(ArtLayer layer) async {
    final pixels = await layerPixels(layer);
    final icc = _icc;
    return Isolate.run(() => encodePngPixels(pixels, icc: icc));
  }

  /// How big an animation export gets on its longest side.
  static int longestSide(ExportFormat format, {required bool web}) => web
      ? 800
      : format == ExportFormat.mp4 || format == ExportFormat.hevc
      ? 1920
      : 2048;

  /// [web]: animations at most 800 px on the longest side.
  Future<Uint8List> export(ExportFormat format, {bool web = false}) async {
    await controller.settleStroke();
    final doc = _doc;
    final background = doc.backgroundHidden ? 0xffffffff : doc.background;
    final icc = _icc, cmyk = _cmyk;
    final settings = doc.animation ?? const AnimationSettings();
    final loop = settings.mode != PlaybackMode.oneShot;
    final longest = longestSide(format, web: web);
    switch (format) {
      case ExportFormat.gif:
        final frames = await animationFrames(longest: longest);
        // No paper: a see-through GIF (pixels under half opaque left out).
        final alpha = doc.backgroundHidden ? .5 : null;
        return Isolate.run(
          () => encodeGif(
            frames,
            loop: loop,
            background: background,
            alphaThreshold: alpha,
          ),
        );
      case ExportFormat.apng:
        final frames = await animationFrames(longest: longest);
        return Isolate.run(() => encodeApng(frames, loop: loop));
      case ExportFormat.mp4 || ExportFormat.hevc:
        return _video(
          await animationFrames(longest: longest),
          settings.fps,
          alpha: format == ExportFormat.hevc,
          background: background,
        );
      case ExportFormat.png:
        final pixels = await composite();
        return Isolate.run(() => encodePngPixels(pixels, icc: icc));
      case ExportFormat.jpeg:
        final pixels = await composite();
        return Isolate.run(
          () => encodeJpeg(pixels, background: background, icc: icc),
        );
      case ExportFormat.tiff:
        final pixels = await composite();
        return Isolate.run(
          () => encodeProfiledTiff(pixels, icc: cmyk ? null : icc, cmyk: cmyk),
        );
      case ExportFormat.pdf:
        final pixels = await composite();
        final dpi = doc.dpi, name = doc.name;
        return Isolate.run(
          () => encodePdf(
            [
              PdfPage(
                encodeJpeg(pixels, background: background),
                pixels.width,
                pixels.height,
                dpi,
              ),
            ],
            title: name,
            icc: icc,
          ),
        );
      case ExportFormat.layersPdf:
        // One page a layer, bottom first, each on the paper; each layer is
        // packed before the next renders.
        final pages = <PdfPage>[];
        for (final layer in doc.layers) {
          final pixels = await layerPixels(layer);
          final jpeg = await Isolate.run(
            () => encodeJpeg(pixels, background: background),
          );
          pages.add(PdfPage(jpeg, pixels.width, pixels.height, doc.dpi));
        }
        final name = doc.name;
        return Isolate.run(() => encodePdf(pages, title: name, icc: icc));
      case ExportFormat.pagesPdf:
        // Page Assist's pages, each on the paper as it is drawn.
        final pages = <PdfPage>[];
        for (var i = 0; i < doc.pages.length; i++) {
          final pixels = await composite(doc.pageOnly(i));
          final jpeg = await Isolate.run(
            () => encodeJpeg(pixels, background: background),
          );
          pages.add(PdfPage(jpeg, pixels.width, pixels.height, doc.dpi));
        }
        final name = doc.name;
        return Isolate.run(() => encodePdf(pages, title: name, icc: icc));
      case ExportFormat.layersPng:
        final archive = Archive();
        final digits = '${doc.layers.length}'.length;
        for (final (i, layer) in doc.layers.indexed) {
          final png = await layerPng(layer);
          final safe = layer.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          archive.addFile(
            ArchiveFile.bytes(
              '${'${i + 1}'.padLeft(digits, '0')} $safe.png',
              png,
            ),
          );
        }
        return Uint8List.fromList(ZipEncoder().encode(archive));
      case ExportFormat.psd:
        return _psd();
    }
  }

  Future<Uint8List> _psd() async {
    final doc = _doc;
    final layers = <PsdLayer>[];
    if (!doc.backgroundHidden) {
      layers.add(
        PsdLayer(name: 'Background', channels: await _pack(_background())),
      );
    }
    String? open;
    void close() {
      final group = doc.groups.where((g) => g.id == open).firstOrNull;
      if (group != null) {
        layers.add(
          PsdLayer(
            name: group.name,
            opacity: group.opacity,
            blend: group.passThrough ? 'pass' : psdBlendKey(group.blend),
            visible: group.visible,
            section: PsdSection.groupStart,
          ),
        );
      }
      open = null;
    }

    for (final layer in doc.layers) {
      if (layer.group != open) {
        close();
        if (layer.group != null) {
          open = layer.group;
          layers.add(
            const PsdLayer(
              name: '</Layer group>',
              section: PsdSection.groupEnd,
            ),
          );
        }
      }
      layers.add(
        PsdLayer(
          name: layer.name,
          channels: await _pack(layerPixels(layer)),
          opacity: layer.opacity,
          blend: psdBlendKey(layer.blend),
          visible: layer.visible,
          clipping: layer.clipping,
        ),
      );
    }
    close();
    final flat = await composite();
    final cmyk = _cmyk, icc = cmyk ? null : _icc;
    final packed = await Isolate.run(() => psdComposite(flat, cmyk: cmyk));
    final CanvasSize(:width, :height) = doc.dimensions;
    return Isolate.run(
      () => encodePsd(width, height, layers, packed, cmyk: cmyk, icc: icc),
    );
  }

  /// Packed off the UI thread; the raw pixels are dropped right after.
  Future<PsdChannels> _pack(Future<RgbaPixels> pixels) async {
    final raw = await pixels;
    final cmyk = _cmyk;
    return Isolate.run(() => psdChannels(raw, cmyk: cmyk));
  }
}
