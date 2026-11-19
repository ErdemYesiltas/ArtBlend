import 'dart:io';

import 'package:atelier_studio/data/studio_storage.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/gallery.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

ArtDocument drawing(String id) {
  final empty = ArtDocument.empty(name: 'Drawing $id');
  return empty.copyWith(id: id);
}

List<String> ids(List<GalleryItem> items) => [for (final i in items) i.id];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the gallery keeps its order and stacks; new drawings come first', () {
    final docs = [
      for (final id in ['d', 'c', 'b', 'a']) drawing(id),
    ];
    final all = [for (final d in docs) d.id];
    var g = GalleryLayout();
    expect(ids(g.arrange(docs)), ['d', 'c', 'b', 'a']);
    g = g.move('a', 'd', all);
    expect(ids(g.arrange(docs)), ['a', 'd', 'c', 'b']);
    g = g.move('d', null, all);
    expect(ids(g.arrange(docs)), ['a', 'c', 'b', 'd']);

    g = g.stackUp('s', 'Pile', ['c', 'b'], all);
    expect(ids(g.arrange(docs)), ['a', 's', 'd']);
    final pile = g.arrange(docs)[1] as GalleryStackItem;
    expect([for (final d in pile.documents) d.id], ['c', 'b']);
    // Dropped on a stack: in it; on one of its drawings: before it.
    g = g.addToStack('d', 's');
    expect(ids(g.arrange(docs)), ['a', 's']);
    g = g.move('d', 'c', all);
    expect(g.stack('s')!.members, ['d', 'c', 'b']);
    g = g.unstackDocument('c', all);
    expect(ids(g.arrange(docs)), ['a', 's', 'c']);
    g = g.placeCopy('d', 'd2', [...all, 'd2']);
    expect(g.stack('s')!.members, ['d', 'd2', 'b']);
    g = g.renameStack('s', 'Sketches');

    final restored = GalleryLayout.fromJson(g.toJson());
    expect(restored.order, g.order);
    expect(restored.stack('s')!.name, 'Sketches');
    expect(
      GalleryLayout.fromJson({
        'stacks': 'x',
        'order': [1, 'a'],
      }).order,
      ['a'],
    );

    final newer = [drawing('e'), ...docs];
    expect(ids(g.arrange(newer)).first, 'e', reason: 'a new drawing on top');
    g = g.dissolve('s', all);
    expect(ids(g.arrange(docs)), ['a', 'd', 'b', 'c']);
    expect(g.stacks, isEmpty);
    expect(
      ids(g.without({'d'}).arrange(docs.where((d) => d.id != 'd').toList())),
      ['a', 'b', 'c'],
    );
    // A stack whose drawings are all gone is not shown.
    final gone = GalleryLayout().stackUp('t', 'T', ['x'], all);
    expect(ids(gone.arrange(docs)), ['d', 'c', 'b', 'a']);
  });

  test('gallery copies, deletions and order are kept on disk; the open '
      'drawing is not touched by them', () async {
    final dir = await Directory.systemTemp.createTemp('artblend-gallery-');
    addTearDown(() => dir.delete(recursive: true));
    final storage = LocalStudioStorage(dir);
    final open = drawing('open'), other = drawing('other');
    await storage.saveDocument(open);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await storage.saveToGallery(other.copyWith(name: 'Renamed'));
    expect((await storage.loadDocument())!.id, 'open');
    final listing = await storage.listDocuments();
    expect([for (final d in listing.documents) d.id], ['other', 'open']);
    expect(listing.documents.first.name, 'Renamed');
    await storage.deleteDocument('other');
    expect(
      [for (final d in (await storage.listDocuments()).documents) d.id],
      ['open'],
    );
    await storage.saveGallery(GalleryLayout(order: ['open']).toJson());
    expect(
      GalleryLayout.fromJson(await LocalStudioStorage(dir).loadGallery()).order,
      ['open'],
    );
  });

  testWidgets('drawings are stacked, opened from a stack, copied and '
      'deleted from the gallery', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = MemoryStorage();
    for (final id in ['a', 'b']) {
      await storage.saveToGallery(drawing(id));
    }
    final c = StudioController(storage: storage);
    await c.initialize();
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    final open = c.document.id;
    c.setPanel(EditorPanel.gallery);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('gallery-$open')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('gallery-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gallery-a')));
    await tester.tap(find.byKey(const ValueKey('gallery-b')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gallery-stack')));
    await tester.pumpAndSettle();
    final layout = GalleryLayout.fromJson(storage.gallery);
    expect(layout.stacks.single.members.toSet(), {'a', 'b'});
    final stack = layout.stacks.single.id;
    expect(find.byKey(const ValueKey('gallery-a')), findsNothing);

    await tester.tap(find.byKey(ValueKey('gallery-$stack')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gallery-a')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('gallery-menu-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate').last);
    await tester.pumpAndSettle();
    expect(storage.documents.length, 4);
    expect(
      GalleryLayout.fromJson(storage.gallery).stacks.single.members,
      hasLength(3),
    );

    await tester.tap(find.byKey(const ValueKey('gallery-back')));
    await tester.pumpAndSettle();
    // The open drawing deleted: another opens in its place.
    await tester.tap(find.byKey(ValueKey('gallery-menu-$open')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gallery-delete-yes')));
    await tester.pumpAndSettle();
    expect(storage.documents.containsKey(open), isFalse);
    expect(c.document.id, isNot(open));
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
