import 'package:material_ui/material_ui.dart';

import '../domain/document.dart';
import '../drawing/brush_engine.dart';
import '../l10n/app_localizations.dart';
import 'overlay_bar.dart';
import 'studio_controller.dart';

/// Page Assist's timeline: each page small, the one shown marked; tap one
/// or step with the arrows.
class PageBar extends StatelessWidget {
  const PageBar({super.key, required this.controller});
  final StudioController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller, l = AppLocalizations.of(context);
    final doc = c.document;
    final pages = doc.pages;
    final current = doc.currentPage;
    final scheme = Theme.of(context).colorScheme;
    const height = 52.0;
    final width =
        height * doc.dimensions.width / doc.dimensions.height.clamp(1, 1 << 20);
    return OverlayBar(
      key: const ValueKey('page-bar'),
      engaged: c.canvasEngaged,
      maxWidth: 900,
      children: [
        Row(
          children: [
            IconButton(
              key: const ValueKey('page-prev'),
              tooltip: l.pagePrevious,
              onPressed: current > 0 ? () => c.goToPage(current - 1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: SizedBox(
                height: height + 22,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: pages.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, i) => InkWell(
                    key: ValueKey('page-$i'),
                    onTap: () => c.goToPage(i),
                    borderRadius: BorderRadius.circular(6),
                    child: Column(
                      children: [
                        Container(
                          width: width.clamp(24, 120),
                          height: height,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: i == current
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                              width: i == current ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: CustomPaint(painter: _PagePainter(c, doc, i)),
                        ),
                        Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: i == current ? FontWeight.w700 : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '${current + 1}/${pages.length}',
                key: const ValueKey('page-count'),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            IconButton(
              key: const ValueKey('page-next'),
              tooltip: l.pageNext,
              onPressed: current < pages.length - 1
                  ? () => c.goToPage(current + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}

class _PagePainter extends CustomPainter {
  _PagePainter(this.c, this.doc, this.index);
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
  bool shouldRepaint(covariant _PagePainter old) =>
      !identical(old.doc, doc) || old.index != index;
}
