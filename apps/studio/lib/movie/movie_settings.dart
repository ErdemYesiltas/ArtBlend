import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/movie.dart';
import '../editor/color_picker.dart';
import '../editor/value_slider.dart';
import '../l10n/app_localizations.dart';

String aspectName(AppLocalizations l, MovieAspect aspect) => switch (aspect) {
  MovieAspect.wide => l.movieAspectWide,
  MovieAspect.cinema => l.movieAspectCinema,
  MovieAspect.portrait => l.movieAspectPortrait,
  MovieAspect.square => l.movieAspectSquare,
  MovieAspect.screen => l.movieAspectScreen,
};

/// "1920×1080 · 24 fps · 0:10".
String movieSummary(MovieDocument m) {
  final total = m.seconds.round();
  final time = '${total ~/ 60}:${'${total % 60}'.padLeft(2, '0')}';
  return '${m.width}×${m.height} · ${m.fps} fps · $time';
}

/// A new movie's settings (name and how it starts too), or an open one's.
/// Pops the movie as set, or null.
class MovieSettingsDialog extends StatefulWidget {
  const MovieSettingsDialog({
    super.key,
    this.movie,
    required this.untitled,
    required this.flipbookName,
    this.recent = const [],
  });

  /// Null: a new movie.
  final MovieDocument? movie;
  final String untitled, flipbookName;
  final List<int> recent;

  @override
  State<MovieSettingsDialog> createState() => _MovieSettingsDialogState();
}

class _MovieSettingsDialogState extends State<MovieSettingsDialog> {
  static const shortSides = [720, 1080, 1440, 2160];

  late final name = TextEditingController(
    text: widget.movie?.name ?? widget.untitled,
  );
  late final width = TextEditingController();
  late final height = TextEditingController();
  late final seconds = TextEditingController();
  late final customFps = TextEditingController();

  MovieStart start = MovieStart.flipbook;
  MovieAspect aspect = MovieAspect.wide;

  /// Null: custom width and height.
  int? short = 1080;
  int fps = 24;
  bool fpsCustom = false;
  int background = 0xffffffff;
  bool transparent = false;
  double offstage = .5;

  double get screenRatio {
    final size = MediaQuery.sizeOf(context);
    return size.height == 0 ? 16 / 9 : size.width / size.height;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (width.text.isNotEmpty) return;
    final m = widget.movie;
    if (m == null) {
      _applySize();
      seconds.text = '10';
    } else {
      width.text = '${m.width}';
      height.text = '${m.height}';
      seconds.text = _trim(m.seconds);
      fps = m.fps;
      fpsCustom = !MovieDocument.fpsPresets.contains(fps);
      background = m.background;
      transparent = m.transparent;
      offstage = m.offstage;
      short = null;
      for (final a in MovieAspect.values) {
        for (final s in shortSides) {
          if (movieSize(a, s, screenRatio: screenRatio) ==
              (m.width, m.height)) {
            aspect = a;
            short = s;
          }
        }
      }
    }
    customFps.text = '$fps';
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2);

  void _applySize() {
    final (w, h) = movieSize(aspect, short!, screenRatio: screenRatio);
    width.text = '$w';
    height.text = '$h';
  }

  @override
  void dispose() {
    for (final c in [name, width, height, seconds, customFps]) {
      c.dispose();
    }
    super.dispose();
  }

  MovieDocument? _result() {
    final w = int.tryParse(width.text), h = int.tryParse(height.text);
    final s = double.tryParse(seconds.text.replaceAll(',', '.'));
    final rate = fpsCustom ? int.tryParse(customFps.text) : fps;
    if (w == null || h == null || s == null || s <= 0 || rate == null) {
      return null;
    }
    final title = name.text.trim().isEmpty ? widget.untitled : name.text.trim();
    final m = widget.movie;
    if (m == null) {
      return MovieDocument.create(
        name: title,
        width: w,
        height: h,
        fps: rate,
        seconds: s,
        background: background,
        transparent: transparent,
        start: start,
        flipbookName: widget.flipbookName,
      ).copyWith(offstage: offstage);
    }
    final next = m.copyWith(
      name: title,
      width: w,
      height: h,
      fps: rate,
      background: background,
      transparent: transparent,
      offstage: offstage,
    );
    return next.copyWith(
      frames: (s.clamp(0, MovieDocument.maxSeconds) * next.fps).round(),
    );
  }

  Future<void> _pickBackground() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      content: SizedBox(
        width: 340,
        child: StatefulBuilder(
          builder: (context, setInner) => ColorPicker(
            color: background,
            onColor: (v) {
              setInner(() {});
              setState(() => background = v);
            },
            recent: widget.recent,
            hexField: const SizedBox.shrink(),
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context).done),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final digits = [FilteringTextInputFormatter.digitsOnly];
    Widget field(
      TextEditingController c,
      String label,
      String key, {
      bool decimal = false,
      VoidCallback? onChanged,
    }) => TextField(
      key: ValueKey(key),
      controller: c,
      decoration: InputDecoration(labelText: label, isDense: true),
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: decimal ? null : digits,
      onChanged: (_) => setState(() => onChanged?.call()),
    );
    final valid = _result() != null;
    return AlertDialog(
      key: const ValueKey('movie-settings'),
      title: Text(widget.movie == null ? l.newMovie : l.movieSettings),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('movie-name'),
                controller: name,
                decoration: InputDecoration(labelText: l.name, isDense: true),
              ),
              if (widget.movie == null) ...[
                const SizedBox(height: 12),
                Text(l.movieStart, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                SegmentedButton<MovieStart>(
                  segments: [
                    ButtonSegment(
                      value: MovieStart.flipbook,
                      label: Text(l.movieStartFlipbook),
                      icon: const Icon(Icons.auto_stories_outlined),
                    ),
                    ButtonSegment(
                      value: MovieStart.blank,
                      label: Text(l.movieStartBlank),
                      icon: const Icon(Icons.crop_landscape),
                    ),
                  ],
                  selected: {start},
                  onSelectionChanged: (v) => setState(() => start = v.single),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<MovieAspect>(
                      key: const ValueKey('movie-aspect'),
                      isExpanded: true,
                      initialValue: aspect,
                      decoration: InputDecoration(
                        labelText: l.movieAspect,
                        isDense: true,
                      ),
                      items: [
                        for (final a in MovieAspect.values)
                          DropdownMenuItem(
                            value: a,
                            child: Text(aspectName(l, a)),
                          ),
                      ],
                      onChanged: (a) => setState(() {
                        aspect = a!;
                        short ??= 1080;
                        _applySize();
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      key: const ValueKey('movie-resolution'),
                      isExpanded: true,
                      initialValue: short,
                      decoration: InputDecoration(
                        labelText: l.movieResolution,
                        isDense: true,
                      ),
                      items: [
                        for (final s in shortSides)
                          DropdownMenuItem(
                            value: s,
                            child: Text(s == 2160 ? '4K' : '${s}p'),
                          ),
                        DropdownMenuItem(
                          value: null,
                          child: Text(l.movieCustomSize),
                        ),
                      ],
                      onChanged: (s) => setState(() {
                        short = s;
                        if (s != null) _applySize();
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: field(
                      width,
                      l.movieWidth,
                      'movie-width',
                      onChanged: () => short = null,
                    ),
                  ),
                  const Text('  ×  '),
                  Expanded(
                    child: field(
                      height,
                      l.movieHeight,
                      'movie-height',
                      onChanged: () => short = null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      key: const ValueKey('movie-fps'),
                      isExpanded: true,
                      initialValue: fpsCustom ? null : fps,
                      decoration: InputDecoration(
                        labelText: l.movieFps,
                        isDense: true,
                      ),
                      items: [
                        for (final f in MovieDocument.fpsPresets)
                          DropdownMenuItem(value: f, child: Text('$f fps')),
                        DropdownMenuItem(
                          value: null,
                          child: Text(l.movieCustomSize),
                        ),
                      ],
                      onChanged: (f) => setState(() {
                        fpsCustom = f == null;
                        if (f != null) fps = f;
                      }),
                    ),
                  ),
                  if (fpsCustom) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: field(
                        customFps,
                        l.movieFpsCustom,
                        'movie-fps-custom',
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: field(
                      seconds,
                      l.movieDuration,
                      'movie-seconds',
                      decimal: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                key: const ValueKey('movie-transparent'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.movieTransparent),
                value: transparent,
                onChanged: (v) => setState(() => transparent = v),
              ),
              if (!transparent)
                ListTile(
                  key: const ValueKey('movie-background'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.movieBackground),
                  trailing: Container(
                    width: 32,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Color(background),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onTap: _pickBackground,
                ),
              ValueSlider(
                id: 'movie-offstage',
                label: l.movieOffstage,
                value: offstage,
                onChanged: (v) => setState(() => offstage = v),
              ),
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
          key: const ValueKey('movie-settings-done'),
          onPressed: valid ? () => Navigator.pop(context, _result()) : null,
          child: Text(widget.movie == null ? l.movieCreate : l.done),
        ),
      ],
    );
  }
}
