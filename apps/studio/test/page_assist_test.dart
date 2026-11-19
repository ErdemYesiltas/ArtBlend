import 'dart:convert';

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/editor/exporter.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

ArtDocument book() => ArtDocument(
  id: 'b',
  name: 'Kitap',
  dimensions: const CanvasSize(120, 80),
  layers: [
    ArtLayer(id: 'a', name: 'Kapak'),
    ArtLayer(id: 'b', name: 'Çizgi', group: 'g'),
    ArtLayer(id: 'c', name: 'Renk', group: 'g'),
    ArtLayer(id: 'd', name: 'Son'),
  ],
  groups: const [LayerGroup(id: 'g', name: 'Sayfa 2')],
  activeLayerId: 'c',
);

List<List<String>> ids(ArtDocument d) => [
  for (final p in d.pages) [for (final l in p) l.id],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each top-level layer or group is a page; a page is drawn alone with '
      'the same layers; the setting is saved', () {
    final doc = book();
    expect(ids(doc), [
      ['a'],
      ['b', 'c'],
      ['d'],
    ]);
    expect(doc.currentPage, 1);
    final only = doc.pageOnly(1);
    expect([for (final l in only.layers) l.id], ['b', 'c']);
    expect(identical(only.layers.first, doc.layers[1]), isTrue);
    expect(only.groups.single.id, 'g');
    expect(doc.pageOnly(0).activeLayerId, 'a');
    final on = doc.copyWith(pageAssist: true);
    expect(
      ArtDocument.fromJson(jsonDecode(jsonEncode(on.toJson()))).pageAssist,
      isTrue,
    );
    expect(
      ArtDocument.fromJson(jsonDecode(jsonEncode(doc.toJson()))).pageAssist,
      isFalse,
    );
  });

  test('with Page Assist the canvas shows the active page; going to a page '
      'makes its top layer active; pages export as PDF pages', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    await c.replaceDocument(book());
    expect(identical(c.shownDocument, c.document), isTrue);
    final undo = c.canUndo;
    c.setPageAssist(true);
    expect(c.canUndo, undo, reason: 'a setting, not an edit');
    expect([for (final l in c.shownDocument.layers) l.id], ['b', 'c']);
    c.goToPage(2);
    expect(c.document.activeLayerId, 'd');
    expect([for (final l in c.shownDocument.layers) l.id], ['d']);
    c.goToPage(9);
    expect(c.document.activeLayerId, 'd');
    final pdf = latin1.decode(await Exporter(c).export(ExportFormat.pagesPdf));
    expect(pdf, contains('/Count 3'));
    c.setPageAssist(false);
    expect(c.shownDocument.layers, hasLength(4));
  });

  testWidgets('the page bar steps and jumps between pages', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await tester.runAsync(() => c.replaceDocument(book()));
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-bar')), findsNothing);
    c.setPageAssist(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-bar')), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('page-0')));
    await tester.pumpAndSettle();
    expect(c.document.activeLayerId, 'a');
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('page-prev')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('page-next')));
    await tester.pumpAndSettle();
    expect(c.document.activeLayerId, 'c', reason: 'the group\'s top layer');
    expect(find.text('2/3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
