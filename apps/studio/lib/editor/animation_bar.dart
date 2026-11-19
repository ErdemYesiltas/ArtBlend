import 'package:material_ui/material_ui.dart';

import '../domain/document.dart';
import '../drawing/brush_engine.dart';
import '../l10n/app_localizations.dart';
import 'color_picker.dart';
import 'overlay_bar.dart';
import 'studio_controller.dart';
import 'value_slider.dart';

/// Animation Assist's timeline (a Flipbook's, in a movie): play or stop,
/// the frames left to right (bottom layer first), the shown one
/// underlined, holds marked; add a frame after the shown one; tap the
/// shown frame for its options. In selection mode several frames are
/// copied, cleared, deleted, reversed or timed at once. It can float as
/// the mini Flipbook. A tap anywhere on it stops playback.
class AnimationBar extends StatefulWidget {
  const AnimationBar({super.key, required this.controller});
  final StudioController controller;

  @override
  State<AnimationBar> createState() => _AnimationBarState();
}

class _AnimationBarState extends State<AnimationBar> {
  /// Selection mode: the chosen frames.
  Set<int>? chosen;

  StudioController get c => widget.controller;

  void _bulk(void Function(Set<int> frames) action) {
    final frames = chosen;
    if (frames == null || frames.isEmpty) return;
    action(frames);
    setState(() => chosen = null);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final doc = c.document;
    final settings = doc.animation!;
    final pages = doc.pages;
    final current = doc.currentPage;
    final scheme = Theme.of(context).colorScheme;
    final picked = chosen;
    if (picked != null) picked.removeWhere((i) => i >= pages.length);
    const height = 52.0;
    final width = (height * doc.dimensions.width / doc.dimensions.height).clamp(
      24.0,
      120.0,
    );
    return OverlayBar(
      key: const ValueKey('animation-bar'),
      engaged: c.canvasEngaged,
      maxWidth: 960,
      children: [
        Row(
          children: [
            ValueListenableBuilder(
              valueListenable: c.playback,
              builder: (context, playing, _) => IconButton(
                key: const ValueKey('animation-play'),
                tooltip: playing == null ? l.timelapsePlay : l.stop,
                onPressed: () => playing == null ? c.play() : c.stopPlayback(),
                icon: Icon(
                  playing == null
                      ? Icons.play_arrow_rounded
                      : Icons.stop_rounded,
                ),
              ),
            ),
            Expanded(
              child: SizedBox(
                height: height + 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: pages.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, i) {
                    final id = ArtDocument.frameId(pages[i]);
                    final hold = settings.hold(id);
                    final pinned =
                        (i == 0 && settings.background == id) ||
                        (i == pages.length - 1 && settings.foreground == id);
                    final selected = picked?.contains(i) ?? false;
                    return InkWell(
                      key: ValueKey('frame-$i'),
                      onTap: () {
                        if (c.stopPlayback()) return c.goToPage(i);
                        if (picked != null) {
                          return setState(
                            () => selected ? picked.remove(i) : picked.add(i),
                          );
                        }
                        if (i != current) return c.goToPage(i);
                        showDialog<void>(
                          context: context,
                          builder: (_) => FrameOptions(controller: c, index: i),
                        );
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              Container(
                                width: width,
                                height: height,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: selected
                                        ? scheme.primary
                                        : pinned
                                        ? scheme.tertiary
                                        : scheme.outlineVariant,
                                    width: selected ? 2.5 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: CustomPaint(
                                  painter: FramePainter(c, doc, i),
                                ),
                              ),
                              if (picked != null)
                                Positioned(
                                  right: 2,
                                  top: 2,
                                  child: Icon(
                                    selected
                                        ? Icons.check_circle
                                        : Icons.circle_outlined,
                                    size: 16,
                                    color: selected
                                        ? scheme.primary
                                        : scheme.outline,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hold > 0 ? '${i + 1} +$hold' : '${i + 1}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: i == current ? FontWeight.w700 : null,
                            ),
                          ),
                          ValueListenableBuilder(
                            valueListenable: c.playback,
                            builder: (context, playing, _) => Container(
                              width: width,
                              height: 3,
                              color: i == (playing ?? current)
                                  ? scheme.primary
                                  : Colors.transparent,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            if (picked == null) ...[
              IconButton(
                key: const ValueKey('frame-select'),
                tooltip: l.framesSelect,
                onPressed: () => setState(() => chosen = {}),
                icon: const Icon(Icons.checklist_rounded),
              ),
              IconButton(
                key: const ValueKey('flipbook-mini'),
                tooltip: '${l.flipbookMini}\n${l.miniFlipbookHint}',
                onPressed: () => c.setMiniFlipbook(true),
                icon: const Icon(Icons.picture_in_picture_alt_outlined),
              ),
              IconButton(
                key: const ValueKey('animation-settings'),
                tooltip: l.animationSettings,
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AnimationSettingsDialog(controller: c),
                ),
                icon: const Icon(Icons.tune),
              ),
              IconButton(
                key: const ValueKey('frame-add'),
                tooltip: l.addFrame,
                onPressed: () => c.addFrame(l.frameName(pages.length + 1)),
                icon: const Icon(Icons.add_box_outlined),
              ),
              barHint(l.frameHint),
            ] else ...[
              Text(
                l.gallerySelected(picked.length),
                style: const TextStyle(fontSize: 12),
              ),
              IconButton(
                key: const ValueKey('frames-duplicate'),
                tooltip: l.galleryDuplicate,
                onPressed: picked.isEmpty
                    ? null
                    : () => _bulk(
                        (f) => c.duplicateFrames(f, (n) => l.frameName(n)),
                      ),
                icon: const Icon(Icons.copy_outlined),
              ),
              IconButton(
                key: const ValueKey('frames-clear'),
                tooltip: l.frameClear,
                onPressed: picked.isEmpty ? null : () => _bulk(c.clearFrames),
                icon: const Icon(Icons.layers_clear_outlined),
              ),
              IconButton(
                key: const ValueKey('frames-reverse'),
                tooltip: l.framesReverse,
                onPressed: picked.length < 2
                    ? null
                    : () => _bulk(c.reverseFrames),
                icon: const Icon(Icons.swap_horiz_rounded),
              ),
              PopupMenuButton<int>(
                key: const ValueKey('frames-duration'),
                tooltip: l.framesDuration,
                enabled: picked.isNotEmpty,
                icon: const Icon(Icons.timer_outlined),
                onSelected: (ticks) =>
                    _bulk((f) => c.setFrameDurations(f, ticks)),
                itemBuilder: (context) => [
                  for (final ticks in [1, 2, 3, 4, 6, 8])
                    PopupMenuItem(
                      value: ticks,
                      child: Text(l.framesTicks(ticks)),
                    ),
                ],
              ),
              IconButton(
                key: const ValueKey('frames-delete'),
                tooltip: l.galleryDelete,
                onPressed: picked.isEmpty || picked.length >= pages.length
                    ? null
                    : () => _bulk(c.deleteFrames),
                icon: const Icon(Icons.delete_outline),
              ),
              IconButton(
                key: const ValueKey('frames-done'),
                tooltip: l.done,
                onPressed: () => setState(() => chosen = null),
                icon: const Icon(Icons.close),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// One frame's options: hold, copy, delete, and background or foreground
/// for the first and last frames.
class FrameOptions extends StatelessWidget {
  const FrameOptions({
    super.key,
    required this.controller,
    required this.index,
  });
  final StudioController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller, doc = c.document;
        final pages = doc.pages, settings = doc.animation;
        if (settings == null || index >= pages.length) {
          return const SizedBox.shrink();
        }
        final id = ArtDocument.frameId(pages[index]);
        return AlertDialog(
          key: const ValueKey('frame-options'),
          title: Text(l.frameOptions),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueSlider(
                  id: 'frame-hold',
                  label: l.frameHold,
                  value: settings.hold(id).toDouble(),
                  max: AnimationSettings.maxHold.toDouble(),
                  toNumber: (v) => v,
                  fromNumber: (n) => n,
                  unit: '',
                  onChanged: (v) => c.setAnimation(
                    settings.copyWith(
                      holds: {...settings.holds, id: v.round()},
                    ),
                  ),
                ),
                if (index == 0)
                  SwitchListTile.adaptive(
                    key: const ValueKey('frame-background'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.frameBackground),
                    value: settings.background == id,
                    onChanged: (on) => c.setFrameOptions(
                      on
                          ? settings.copyWith(background: id)
                          : settings.copyWith(clearBackground: true),
                    ),
                  ),
                if (index == pages.length - 1 && pages.length > 1)
                  SwitchListTile.adaptive(
                    key: const ValueKey('frame-foreground'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.frameForeground),
                    value: settings.foreground == id,
                    onChanged: (on) => c.setFrameOptions(
                      on
                          ? settings.copyWith(foreground: id)
                          : settings.copyWith(clearForeground: true),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            if (settings.hold(id) > 0)
              TextButton(
                key: const ValueKey('frame-split'),
                onPressed: () {
                  Navigator.pop(context);
                  c.splitFrame(index, l.frameName(pages.length + 1));
                },
                child: Text(l.frameSplit),
              ),
            TextButton(
              key: const ValueKey('frame-clear'),
              onPressed: () {
                Navigator.pop(context);
                c.clearFrames({index});
              },
              child: Text(l.frameClear),
            ),
            TextButton(
              key: const ValueKey('frame-delete'),
              onPressed: pages.length < 2
                  ? null
                  : () {
                      Navigator.pop(context);
                      c.deleteFrame(index);
                    },
              child: Text(l.galleryDelete),
            ),
            TextButton(
              key: const ValueKey('frame-duplicate'),
              onPressed: () {
                Navigator.pop(context);
                c.duplicateFrame(index, l.frameName(pages.length + 1));
              },
              child: Text(l.duplicateLayer),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.done),
            ),
          ],
        );
      },
    );
  }
}

/// Playback and onion skins: fps, loop mode, how many frames show each
/// side, how strongly, in which tints, and the frame drawn on see-through.
class AnimationSettingsDialog extends StatelessWidget {
  const AnimationSettingsDialog({super.key, required this.controller});
  final StudioController controller;

  Future<void> _tint(
    BuildContext context,
    int color,
    ValueChanged<int> onColor,
  ) => showDialog<void>(
    context: context,
    builder: (context) {
      var current = color;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          content: SizedBox(
            width: 340,
            child: ColorPicker(
              color: current,
              onColor: (v) {
                setState(() => current = v);
                onColor(v);
              },
              recent: controller.recentColors,
              hexField: const SizedBox.shrink(),
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
    },
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller, settings = c.document.animation;
        if (settings == null) return const SizedBox.shrink();
        void set(AnimationSettings next) => c.setAnimation(next);
        Widget swatch(
          String key,
          String label,
          int color,
          ValueChanged<int> on,
        ) => ListTile(
          key: ValueKey(key),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(label),
          trailing: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Color(color),
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          onTap: () => _tint(context, color, on),
        );
        return AlertDialog(
          key: const ValueKey('animation-settings-dialog'),
          title: Text(l.animationSettings),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<PlaybackMode>(
                    key: const ValueKey('playback-mode'),
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: PlaybackMode.loop,
                        label: Text(l.playbackLoop),
                      ),
                      ButtonSegment(
                        value: PlaybackMode.pingPong,
                        label: Text(l.playbackPingPong),
                      ),
                      ButtonSegment(
                        value: PlaybackMode.oneShot,
                        label: Text(l.playbackOneShot),
                      ),
                    ],
                    selected: {settings.mode},
                    onSelectionChanged: (v) =>
                        set(settings.copyWith(mode: v.single)),
                  ),
                  const SizedBox(height: 8),
                  ValueSlider(
                    id: 'animation-fps',
                    label: l.framesPerSecond,
                    labelWidth: 120,
                    value: settings.fps.toDouble(),
                    min: 1,
                    max: 60,
                    toNumber: (v) => v,
                    fromNumber: (n) => n,
                    unit: '',
                    onChanged: (v) => set(settings.copyWith(fps: v.round())),
                  ),
                  ValueSlider(
                    id: 'onion-frames',
                    label: l.onionFrames,
                    labelWidth: 120,
                    value: settings.onionFrames.toDouble(),
                    max: AnimationSettings.maxOnion.toDouble(),
                    toNumber: (v) => v,
                    fromNumber: (n) => n,
                    unit: '',
                    onChanged: (v) =>
                        set(settings.copyWith(onionFrames: v.round())),
                  ),
                  ValueSlider(
                    id: 'onion-opacity',
                    label: l.onionOpacity,
                    labelWidth: 120,
                    value: settings.onionOpacity,
                    onChanged: (v) => set(settings.copyWith(onionOpacity: v)),
                  ),
                  SwitchListTile.adaptive(
                    key: const ValueKey('blend-primary'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.blendPrimary),
                    value: settings.blendPrimary,
                    onChanged: (v) => set(settings.copyWith(blendPrimary: v)),
                  ),
                  swatch(
                    'onion-behind',
                    l.onionBehind,
                    settings.onionBehind,
                    (v) => set(c.document.animation!.copyWith(onionBehind: v)),
                  ),
                  swatch(
                    'onion-ahead',
                    l.onionAhead,
                    settings.onionAhead,
                    (v) => set(c.document.animation!.copyWith(onionAhead: v)),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.done),
            ),
          ],
        );
      },
    );
  }
}

/// Frame [index] of [doc], small.
class FramePainter extends CustomPainter {
  FramePainter(this.c, this.doc, this.index);
  final StudioController c;
  final ArtDocument doc;
  final int index;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / doc.dimensions.width);
    paintDocument(
      canvas,
      doc.pageOnly(index),
      FreehandBrushEngine(),
      rasterImages: c.rasters.images,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FramePainter old) =>
      !identical(old.doc, doc) || old.index != index;
}
