import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import 'animation_bar.dart';
import 'studio_controller.dart';

const _cell = 40.0, _visible = 8, _edge = 56.0;

/// Which way the mini Flipbook lies at [at] in [workspace]: upright by the
/// left or right edge, lying down elsewhere.
Axis miniFlipbookAxis(Offset at, Size workspace, double length) =>
    at.dx <= _edge || at.dx + _cell + 16 >= workspace.width - _edge
    ? Axis.vertical
    : Axis.horizontal;

/// Where a mini Flipbook dropped at [at] settles: locked to the left,
/// right or top edge when near it; null when dropped at the bottom (the
/// timeline comes back).
Offset? settleMiniFlipbook(Offset at, Size workspace, Size size) {
  if (at.dy + size.height >= workspace.height - _edge) return null;
  var x = at.dx
      .clamp(0.0, math.max(0.0, workspace.width - size.width))
      .toDouble();
  var y = at.dy
      .clamp(0.0, math.max(0.0, workspace.height - size.height))
      .toDouble();
  if (x <= _edge) x = 8;
  if (x + size.width >= workspace.width - _edge) {
    x = workspace.width - size.width - 8;
  }
  if (y <= _edge) y = 8;
  return Offset(x, y);
}

/// Dreams' mini Flipbook: the frames as a small strip floating over the
/// canvas. Drag the handle to move it (it locks to the edges), drop it at
/// the bottom or double-tap the handle to dock it; drag along the frames
/// to scrub.
class MiniFlipbook extends StatefulWidget {
  const MiniFlipbook({
    super.key,
    required this.controller,
    required this.workspace,
  });
  final StudioController controller;
  final Size workspace;

  @override
  State<MiniFlipbook> createState() => _MiniFlipbookState();
}

class _MiniFlipbookState extends State<MiniFlipbook> {
  final _scroll = ScrollController();

  StudioController get c => widget.controller;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Size _size(Axis axis, int frames) {
    final length = math.min(frames, _visible) * _cell + 44;
    return axis == Axis.vertical
        ? Size(_cell + 16, length)
        : Size(length, _cell + 16);
  }

  void _scrub(Offset local, Axis axis, int frames) {
    final along = axis == Axis.vertical ? local.dy : local.dx;
    final i = ((along + _scroll.offset) / _cell).floor();
    if (i >= 0 && i < frames && i != c.document.currentPage) {
      c.stopPlayback();
      c.goToPage(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final doc = c.document, pages = doc.pages;
    final current = doc.currentPage;
    final at = c.miniFlipbookAt;
    final axis = miniFlipbookAxis(at, widget.workspace, pages.length * _cell);
    final size = _size(axis, pages.length);
    final strip = GestureDetector(
      onTapUp: (d) => _scrub(d.localPosition, axis, pages.length),
      onHorizontalDragUpdate: axis == Axis.horizontal
          ? (d) => _scrub(d.localPosition, axis, pages.length)
          : null,
      onVerticalDragUpdate: axis == Axis.vertical
          ? (d) => _scrub(d.localPosition, axis, pages.length)
          : null,
      child: ListView.builder(
        key: const ValueKey('mini-flipbook-frames'),
        controller: _scroll,
        scrollDirection: axis,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: pages.length,
        itemExtent: _cell,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.all(2),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border.all(
                color: i == current ? scheme.primary : scheme.outlineVariant,
                width: i == current ? 2.5 : 1,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CustomPaint(painter: FramePainter(c, doc, i)),
            ),
          ),
        ),
      ),
    );
    // The shown frame stays in view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients || current < 0) return;
      final view = _scroll.position.viewportDimension;
      final start = current * _cell, end = start + _cell;
      if (start < _scroll.offset) _scroll.jumpTo(start);
      if (end > _scroll.offset + view) {
        _scroll.jumpTo(math.min(end - view, _scroll.position.maxScrollExtent));
      }
    });
    final handle = GestureDetector(
      key: const ValueKey('mini-flipbook-handle'),
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => c.moveMiniFlipbook(at + d.delta),
      onPanEnd: (_) {
        final settled = settleMiniFlipbook(
          c.miniFlipbookAt,
          widget.workspace,
          size,
        );
        settled == null
            ? c.setMiniFlipbook(false)
            : c.moveMiniFlipbook(settled);
      },
      onDoubleTap: () => c.setMiniFlipbook(false),
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: SizedBox(
          width: axis == Axis.vertical ? _cell + 16 : 20,
          height: axis == Axis.vertical ? 20 : _cell + 16,
          child: Center(
            child: Container(
              width: axis == Axis.vertical ? 24 : 4,
              height: axis == Axis.vertical ? 4 : 24,
              decoration: BoxDecoration(
                color: scheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
    return Positioned(
      left: at.dx.clamp(0, math.max(0, widget.workspace.width - size.width)),
      top: at.dy.clamp(0, math.max(0, widget.workspace.height - size.height)),
      width: size.width,
      height: size.height,
      child: Material(
        key: const ValueKey('mini-flipbook'),
        elevation: 8,
        color: scheme.surface.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Flex(
          direction: axis,
          children: [
            handle,
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: axis == Axis.vertical ? 6 : 0,
                  vertical: axis == Axis.vertical ? 0 : 6,
                ),
                child: strip,
              ),
            ),
            SizedBox(
              width: axis == Axis.vertical ? _cell + 16 : 24,
              height: axis == Axis.vertical ? 24 : _cell + 16,
              child: ValueListenableBuilder(
                valueListenable: c.playback,
                builder: (context, playing, _) => IconButton(
                  key: const ValueKey('mini-flipbook-play'),
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  tooltip: playing == null ? l.timelapsePlay : l.stop,
                  onPressed: () =>
                      playing == null ? c.play() : c.stopPlayback(),
                  icon: Icon(
                    playing == null
                        ? Icons.play_arrow_rounded
                        : Icons.stop_rounded,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
