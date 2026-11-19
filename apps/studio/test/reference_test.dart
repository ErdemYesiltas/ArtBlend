import 'dart:typed_data';

import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

/// Left half blue, right half orange.
Uint8List picture() {
  final image = img.Image(width: 200, height: 100);
  for (var y = 0; y < 100; y++) {
    for (var x = 0; x < 200; x++) {
      image.setPixelRgb(
        x,
        y,
        x < 100 ? 20 : 240,
        x < 100 ? 60 : 140,
        x < 100 ? 220 : 20,
      );
    }
  }
  return img.encodePng(image);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the reference picks colours from its picture, or from the canvas',
    () async {
      final c = StudioController(storage: MemoryStorage());
      addTearDown(c.dispose);
      await c.initialize();
      await c.setReferenceImage(picture());
      expect(c.referenceOpen, isTrue);
      expect(c.referenceImage!.width, 200);
      c.pickFromReference(const Offset(150, 50));
      expect(c.color, 0xfff08c14);
      c.pickFromReference(const Offset(10, 10));
      expect(c.color, 0xff143cdc);

      c.clearReferenceImage();
      c.selectColor(0xff33aa55);
      c.setSelection(
        SelectionRegion.rectangle(const Rect.fromLTWH(0, 0, 200, 200)),
      );
      await c.fillActiveLayer();
      c.setSelection(null);
      c.selectColor(0xff000000);
      c.pickFromReference(const Offset(50, 50));
      for (var i = 0; i < 100 && c.color == 0xff000000; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(c.color, 0xff33aa55, reason: 'the canvas under the tap');
    },
  );

  testWidgets('the reference window moves, grows, picks and closes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await tester.runAsync(() => c.setReferenceImage(picture()));
    await tester.pumpWidget(StudioApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reference-window')), findsOneWidget);
    final before = c.referenceRect;
    await tester.drag(
      find.byKey(const ValueKey('reference-bar')),
      const Offset(120, 60),
    );
    await tester.pumpAndSettle();
    expect(c.referenceRect.left, greaterThan(before.left + 60));
    expect(c.referenceRect.size, before.size);
    await tester.drag(
      find.byKey(const ValueKey('reference-resize')),
      const Offset(100, 50),
    );
    await tester.pumpAndSettle();
    expect(c.referenceRect.width, greaterThan(before.width + 50));

    // The view's right half is the picture's orange.
    final view = tester.getRect(find.byKey(const ValueKey('reference-view')));
    await tester.tapAt(view.center + Offset(view.width / 4, 0));
    await tester.pumpAndSettle();
    expect(c.color, 0xfff08c14);

    await tester.tap(find.byKey(const ValueKey('reference-close')));
    await tester.pumpAndSettle();
    expect(c.referenceOpen, isFalse);
    expect(find.byKey(const ValueKey('reference-window')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
