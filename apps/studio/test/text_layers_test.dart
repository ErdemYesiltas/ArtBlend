import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/drawing/text_layer.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a text layer is saved with its style; damaged text is refused', () {
    const text = LayerText(
      text: 'Merhaba\ndünya',
      origin: Offset(10, 20),
      width: 300,
      font: 'serif',
      weight: 700,
      italic: true,
      size: 48,
      tracking: .1,
      leading: 1.5,
      baseline: .2,
      alignment: TextAlignment.center,
      underline: true,
      outline: true,
      vertical: true,
      uppercase: true,
      color: 0xff112233,
    );
    expect(LayerText.fromJson(text.toJson()), text);
    final layer = ArtLayer(id: 'a', name: 'Merhaba', text: text);
    final grid = TileGrid(const CanvasSize(512, 512));
    expect(ArtLayer.fromJson(layer.toJson(), grid).text, text);
    expect(
      ArtLayer.fromJson(ArtLayer(id: 'b', name: 'b').toJson(), grid).text,
      isNull,
    );
    expect(text.shown, 'MERHABA\nDÜNYA');
    expect(
      () => LayerText.fromJson({
        'text': 3,
        'origin': [0, 0],
      }),
      throwsFormatException,
    );
    expect(text.copyWith(weight: 1200).weight, 900);
  });

  test('the text box is as wide as set and as tall as the text; vertical '
      'text stacks its letters', () {
    const line = LayerText(
      text: 'Hi',
      origin: Offset(10, 10),
      width: 400,
      size: 40,
    );
    final one = textBounds(line);
    expect(one.left, 10);
    expect(one.width, 400);
    final two = textBounds(line.copyWith(text: 'Hi\nthere'));
    expect(two.height, greaterThan(one.height * 1.8));
    final vertical = textBounds(line.copyWith(vertical: true));
    expect(vertical.height, greaterThan(one.height * 1.8));
    expect(vertical.width, lessThan(100));
  });

  test('adding and editing text is one undo step each; painting on it asks '
      'to rasterise; rasterising and clearing turn it into pixels', () async {
    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    final layers = c.document.layers.length;
    c.selectColor(0xffaa0000);
    c.addText('Text');
    final id = c.textEditing!;
    expect(c.document.activeLayerId, id);
    expect(c.editedText!.color, 0xffaa0000);
    for (final word in ['M', 'Me', 'Mer']) {
      c.setText((t) => t.copyWith(text: word));
    }
    c.setText((t) => t.copyWith(weight: 700));
    expect(c.document.activeLayer.name, 'Mer', reason: 'named by its text');
    c.selectColor(0xff00aa00);
    expect(c.editedText!.color, 0xff00aa00, reason: 'colour goes to text');
    c.finishText();
    expect(c.textEditing, isNull);
    c.undo();
    expect(c.document.layers.length, layers, reason: 'one step');

    c.redo();
    c.editText(id);
    c.setText((t) => t.copyWith(origin: const Offset(5, 5)));
    c.setText((t) => t.copyWith(width: 200));
    c.finishText();
    c.undo();
    expect(c.document.activeLayer.text!.origin, isNot(const Offset(5, 5)));
    expect(c.document.activeLayer.text!.text, 'Mer');
    c.redo();

    final touched = c.textLayerTouched.value;
    expect(
      c.beginStroke(const InkPoint(50, 50, .5), simulatePressure: false),
      isFalse,
    );
    expect(c.textLayerTouched.value, touched + 1);

    await c.rasterizeText(id);
    final layer = c.document.layers.firstWhere((l) => l.id == id);
    expect(layer.text, isNull);
    expect(layer.raster, isNotNull, reason: 'its pixels stay');
    expect(
      c.beginStroke(const InkPoint(50, 50, .5), simulatePressure: false),
      isTrue,
    );
    c.cancelStroke();

    c.addText('');
    final empty = c.textEditing!;
    c.finishText();
    expect(
      c.document.layers.any((l) => l.id == empty),
      isFalse,
      reason: 'no text, no layer',
    );

    c.addText('x');
    final cleared = c.textEditing!;
    c.finishText();
    c.clearLayer(cleared);
    expect(c.document.layers.firstWhere((l) => l.id == cleared).text, isNull);
  });

  testWidgets('the text bar types and styles the text; its box moves on the '
      'canvas and a tap outside finishes', (tester) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    c.addText('Text');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('text-bar')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('text-field')), 'Selam');
    await tester.pump();
    expect(c.editedText!.text, 'Selam');
    await tester.tap(find.byKey(const ValueKey('text-bold')));
    await tester.tap(find.byKey(const ValueKey('text-align')));
    await tester.pump();
    expect(c.editedText!.weight, 700);
    expect(c.editedText!.alignment, TextAlignment.center);

    final surface = find.byKey(const ValueKey('drawing-surface'));
    final box = tester.renderObject<RenderBox>(surface);
    final scale = box.size.width / c.document.dimensions.width;
    final start = c.editedText!.origin;
    final inside = box.localToGlobal(textBounds(c.editedText!).center * scale);
    final drag = await tester.startGesture(
      inside,
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 1; i <= 5; i++) {
      await drag.moveTo(inside + Offset(i * 10.0, 0));
      await tester.pump();
    }
    await drag.up();
    await tester.pump();
    expect(c.editedText!.origin.dx - start.dx, closeTo(50 / scale, 1));
    expect(c.document.layers.where((l) => l.text != null).length, 1);

    // Outside the box, clear of the bars over the canvas.
    await tester.tapAt(
      box.localToGlobal(Offset(box.size.width * .1, box.size.height * .7)),
    );
    await tester.pumpAndSettle();
    expect(c.textEditing, isNull);
    expect(find.byKey(const ValueKey('text-bar')), findsNothing);
    expect(c.document.activeLayer.strokes, isEmpty, reason: 'no ink');

    // A double tap on the text opens it again, without asking to rasterise.
    final text = box.localToGlobal(
      textBounds(c.document.activeLayer.text!).center * scale,
    );
    for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
      c.finishText();
      await tester.pumpAndSettle();
      await tester.tapAt(text, kind: kind);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(text, kind: kind);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(c.textEditing, c.document.activeLayerId, reason: kind.name);
      expect(find.byKey(const ValueKey('rasterize-yes')), findsNothing);
    }
    // One tap on it with the brush asks.
    c.finishText();
    await tester.pumpAndSettle();
    await tester.tapAt(text);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(c.textEditing, isNull);
    expect(find.byKey(const ValueKey('rasterize-yes')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rasterize-yes')));
    for (var i = 0; i < 100 && c.document.activeLayer.text != null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(c.document.activeLayer.text, isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
