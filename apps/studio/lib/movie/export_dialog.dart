import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../editor/value_slider.dart';
import '../l10n/app_localizations.dart';
import 'movie_controller.dart';
import 'movie_export.dart';

String movieFormatName(AppLocalizations l, MovieFormat f) => switch (f) {
  MovieFormat.mp4 => l.exportMp4,
  MovieFormat.hevc => l.exportHevc,
  MovieFormat.gif => l.exportGif,
  MovieFormat.png => l.exportPngFrames,
  MovieFormat.jpeg => l.exportJpegFrames,
  MovieFormat.tiff => l.exportTiffFrames,
  MovieFormat.tga => l.exportTgaFrames,
  MovieFormat.bmp => l.exportBmpFrames,
  MovieFormat.frame => l.exportFrame,
  MovieFormat.project => l.exportProject,
};

/// The movie exported as the user picks (format, preview size, GIF
/// settings), with progress, then saved where they say.
Future<void> exportMovie(BuildContext context, MovieController c) async {
  final l = AppLocalizations.of(context);
  final options = await showDialog<MovieExportOptions>(
    context: context,
    builder: (_) => _ExportDialog(transparent: c.movie.transparent),
  );
  if (options == null || !context.mounted) return;
  c.stop();
  final done = ValueNotifier(0.0);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      key: const ValueKey('export-progress'),
      content: ValueListenableBuilder(
        valueListenable: done,
        builder: (context, value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.exportWorking),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: value == 0 ? null : value),
          ],
        ),
      ),
    ),
  );
  String? failure;
  try {
    final bytes = await MovieExporter(c)
        .export(options, progress: (v) => done.value = v);
    if (context.mounted) Navigator.pop(context);
    await FilePicker.saveFile(
      fileName: '${c.movie.name}.${options.format.extension}',
      bytes: bytes,
      mimeType: options.format.mimeType,
    );
  } catch (e) {
    if (context.mounted) Navigator.pop(context);
    failure = '$e';
  } finally {
    done.dispose();
  }
  if (failure != null && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.operationFailed(failure))));
  }
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.transparent});
  final bool transparent;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  MovieFormat format = MovieFormat.mp4;
  bool preview = false, dither = true;
  double colors = 256, alpha = .5;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('movie-export'),
      title: Text(l.exportMovie),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<MovieFormat>(
                key: const ValueKey('export-format'),
                initialValue: format,
                isExpanded: true,
                items: [
                  for (final f in MovieFormat.values)
                    if (f != MovieFormat.hevc || Platform.isMacOS)
                      DropdownMenuItem(
                        value: f,
                        child: Text(movieFormatName(l, f)),
                      ),
                ],
                onChanged: (f) => setState(() => format = f!),
              ),
              if (format != MovieFormat.project)
                SwitchListTile.adaptive(
                  key: const ValueKey('export-preview'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.exportPreview),
                  value: preview,
                  onChanged: (v) => setState(() => preview = v),
                ),
              if (format == MovieFormat.gif) ...[
                ValueSlider(
                  id: 'export-gif-colors',
                  label: l.exportColors,
                  value: colors,
                  min: 2,
                  max: 256,
                  toNumber: (v) => v,
                  fromNumber: (n) => n,
                  unit: '',
                  onChanged: (v) => setState(() => colors = v.roundToDouble()),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.exportDither),
                  value: dither,
                  onChanged: (v) => setState(() => dither = v),
                ),
                if (widget.transparent)
                  ValueSlider(
                    id: 'export-gif-alpha',
                    label: l.exportAlphaThreshold,
                    value: alpha,
                    onChanged: (v) => setState(() => alpha = v),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('export-go'),
          onPressed: () => Navigator.pop(
            context,
            MovieExportOptions(
              format,
              preview: preview,
              gifColors: colors.round(),
              gifDither: dither,
              alphaThreshold: alpha,
            ),
          ),
          child: Text(l.exportGo),
        ),
      ],
    );
  }
}
