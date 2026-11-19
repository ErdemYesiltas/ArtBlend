import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/drawing/brush_engine.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

Future<Uint8List> shown(StudioController c) async {
  final recorder = ui.PictureRecorder();
  final doc = c.document.copyWith(backgroundHidden: true);
  paintDocument(
    ui.Canvas(recorder),
    doc,
    FreehandBrushEngine(),
    rasterImages: c.rasters.images,
  );
  final image = await recorder.endRecording().toImage(
    doc.dimensions.width,
    doc.dimensions.height,
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

List<int> at(StudioController c, Uint8List pixels, int x, int y) {
  final i = (y * c.document.dimensions.width + x) * 4;
  return pixels.sublist(i, i + 4);
}

/// Three layers: red, green over its right half, blue over the right
/// quarter; each named after its colour.
Future<StudioController> three() async {
  final c = StudioController(storage: MemoryStorage());
  await c.initialize();
  c.updateLayer(c.document.activeLayerId, (l) => l.copyWith(name: 'red'));
  for (final (name, color, left) in [
    ('red', 0xffff0000, 0.0),
    ('green', 0xff00ff00, 512.0),
    ('blue', 0xff0000ff, 768.0),
  ]) {
    if (name != 'red') c.addLayer(name);
    c.selectColor(color);
    c.setSelection(
      SelectionRegion.rectangle(Rect.fromLTWH(left, 0, 1024 - left, 1024)),
    );
    await c.fillActiveLayer();
  }
  c.setSelection(null);
  return c;
}

String names(StudioController c) => [
  for (final l in c.document.layers) '${l.name}${l.group == null ? '' : '*'}',
].join(' ');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('groups are saved and checked; an emptied group goes', () {
    final group = const LayerGroup(id: 'g', name: 'G', opacity: .5);
    final doc = ArtDocument(
      id: 'd',
      name: 'D',
      layers: [
        ArtLayer(id: 'a', name: 'a'),
        ArtLayer(id: 'b', name: 'b', group: 'g'),
        ArtLayer(id: 'c', name: 'c', group: 'g'),
      ],
      activeLayerId: 'a',
      groups: [group],
    );
    final back = ArtDocument.fromJson(doc.toJson());
    expect(back.groups.single.opacity, .5);
    expect(back.layers.map((l) => l.group), [null, 'g', 'g']);
    expect(
      () => doc.copyWith(layers: [doc.layers[1], doc.layers[0], doc.layers[2]]),
      throwsFormatException,
      reason: 'a group\'s layers stay together',
    );
    expect(doc.copyWith(layers: [doc.layers.first]).groups, isEmpty);
  });

  test('a hidden group hides its layers; a faded group fades as one', () async {
    final c = await three();
    addTearDown(c.dispose);
    c.selectLayer(c.document.layers[1].id);
    c.toggleLayerChoice(c.document.layers[2].id);
    c.groupLayers('G');
    expect(names(c), 'red green* blue*');
    final id = c.document.groups.single.id;
    var pixels = await shown(c);
    expect(at(c, pixels, 900, 10), [0, 0, 255, 255]);
    c.updateGroup(id, (g) => g.copyWith(visible: false));
    pixels = await shown(c);
    expect(at(c, pixels, 900, 10), [255, 0, 0, 255]);
    expect(at(c, pixels, 600, 10), [255, 0, 0, 255]);
    c.updateGroup(id, (g) => g.copyWith(visible: true, opacity: .5));
    pixels = await shown(c);
    // Blue covers green inside the group; the group at half over red.
    expect(at(c, pixels, 900, 10)[0], closeTo(128, 2));
    expect(at(c, pixels, 900, 10)[1], closeTo(0, 2));
    expect(at(c, pixels, 900, 10)[2], closeTo(128, 2));
    c.undo();
    c.undo();
    expect(c.document.groups.single.visible, isTrue);
    expect(c.document.groups.single.opacity, 1);
  });

  test('new layers join the active one\'s group; layers move in and out; '
      'groups move whole and come apart', () async {
    final c = await three();
    addTearDown(c.dispose);
    c.groupLayers('G', ids: [c.document.layers[1].id]);
    final id = c.document.groups.single.id;
    c.selectLayer(c.document.layers[1].id);
    c.addLayer('new');
    expect(names(c), 'red green* new* blue');
    final blue = c.document.layers[3].id;
    c.placeLayer(blue, 2, group: id);
    expect(names(c), 'red green* blue* new*');
    c.placeLayer(c.document.layers[3].id, 3);
    expect(names(c), 'red green* blue* new');
    c.placeGroup(id, 0);
    expect(names(c), 'green* blue* red new');
    // Dropped inside the group without joining: it goes above it.
    c.placeLayer(c.document.layers[3].id, 1);
    expect(names(c), 'green* new* blue* red');
    c.ungroup(id);
    expect(names(c), 'green new blue red');
    expect(c.document.groups, isEmpty);
    c.groupLayers('H', ids: [c.document.layers[0].id, c.document.layers[3].id]);
    expect(names(c), 'new blue green* red*');
    c.deleteGroup(c.document.groups.single.id);
    expect(names(c), 'new blue');
  });

  test('chosen layers merge into one, looking the same, as one step', () async {
    final c = await three();
    addTearDown(c.dispose);
    final before = await shown(c);
    c.selectLayer(c.document.layers[0].id);
    for (final l in c.document.layers.skip(1)) {
      c.toggleLayerChoice(l.id);
    }
    expect(c.chosenLayers, hasLength(3));
    await c.mergeLayers(c.chosenLayers.map((l) => l.id));
    expect(c.document.layers, hasLength(1));
    expect(c.selectedLayers, isEmpty);
    final after = await shown(c);
    for (final x in [100, 600, 900]) {
      expect(at(c, after, x, 10), at(c, before, x, 10));
    }
    c.undo();
    await c.settleStroke();
    expect(c.document.layers, hasLength(3));
  });

  testWidgets('the panel folds groups, chooses by swiping right, groups '
      'and merges by pinching', (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late StudioController c;
    await tester.runAsync(() async => c = await three());
    c.setPanel(EditorPanel.layers);
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    await tester.fling(find.text('green'), const Offset(120, 0), 800);
    await tester.pumpAndSettle();
    expect(c.selectedLayers, {c.document.layers[1].id});
    expect(find.text('2 layers chosen'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('choice-group')));
    await tester.pumpAndSettle();
    final group = c.document.groups.single;
    expect(find.text(group.name), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('group-fold-${group.id}')));
    await tester.pumpAndSettle();
    expect(find.text('green'), findsNothing);
    await tester.tap(find.byKey(ValueKey('group-fold-${group.id}')));
    await tester.pumpAndSettle();
    expect(find.text('green'), findsOneWidget);

    // Pinch green and red together: they merge.
    final a = tester.getCenter(find.text('green'));
    final b = tester.getCenter(find.text('red'));
    final first = await tester.startGesture(a, kind: PointerDeviceKind.touch);
    final second = await tester.startGesture(b, kind: PointerDeviceKind.touch);
    final middle = (a + b) / 2;
    await first.moveTo(middle - const Offset(0, 4));
    await second.moveTo(middle + const Offset(0, 4));
    await tester.runAsync(() async {
      await first.up();
      await second.up();
      for (var i = 0; i < 50 && c.document.layers.length == 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(c.document.layers.map((l) => l.name), ['red', 'blue']);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
