import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/selection.dart';
import 'package:atelier_studio/editor/studio_controller.dart';
import 'package:atelier_studio/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a private layer is saved as one; pasting privately and copying a '
      'private layer keep it private; marking is an undo step', () async {
    final grid = TileGrid(const CanvasSize(64, 64));
    final layer = ArtLayer(id: 'p', name: 'Fotoğraf', private: true);
    expect(ArtLayer.fromJson(layer.toJson(), grid).private, isTrue);
    expect(
      ArtLayer.fromJson(ArtLayer(id: 'x', name: 'x').toJson(), grid).private,
      isFalse,
    );

    final c = StudioController(storage: MemoryStorage());
    addTearDown(c.dispose);
    await c.initialize();
    c.setSelection(
      SelectionRegion.rectangle(const Rect.fromLTWH(0, 0, 50, 50)),
    );
    await c.fillActiveLayer();
    c.setSelection(null);
    expect(await c.copy(), isTrue);
    await c.paste('Pasted', private: true);
    expect(c.document.activeLayer.private, isTrue);
    await c.paste('Pasted');
    expect(c.document.activeLayer.private, isFalse);

    final id = c.document.activeLayerId;
    c.togglePrivateLayer(id);
    expect(c.document.activeLayer.private, isTrue);
    c.duplicateLayer(id, 'Copy');
    expect(c.document.activeLayer.private, isTrue);
    c.undo();
    c.undo();
    expect(c.document.layers.firstWhere((l) => l.id == id).private, isFalse);
  });

  testWidgets('the layer menu marks a layer private and its row says so', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StudioController(storage: MemoryStorage());
    await c.initialize();
    await tester.pumpWidget(StudioApp(controller: c));
    c.setPanel(EditorPanel.layers);
    await tester.pumpAndSettle();
    final id = c.document.activeLayerId;
    expect(find.byKey(ValueKey('layer-private-$id')), findsNothing);
    await tester.tap(find.text(c.document.activeLayer.name).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Private').last);
    await tester.pumpAndSettle();
    expect(c.document.activeLayer.private, isTrue);
    expect(find.byKey(ValueKey('layer-private-$id')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
