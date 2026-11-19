import 'dart:ui' as ui;

import 'package:atelier_studio/domain/layer_text.dart';
import 'package:atelier_studio/domain/movie.dart';
import 'package:atelier_studio/l10n/app_localizations.dart';
import 'package:atelier_studio/movie/movie_controller.dart';
import 'package:atelier_studio/movie/movie_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/memory_storage.dart';

MovieDocument film() => MovieDocument(
  id: 'm',
  name: 'Film',
  width: 400,
  height: 200,
  fps: 10,
  frames: 40,
);

void main() {
  testWidgets('a text content holds still-editable words, drawn like any '
      'drawing; editing them is one undo step for its name', (tester) async {
    final c = MovieController(storage: MemoryStorage(), movie: film());
    addTearDown(c.dispose);
    c.seek(5);
    c.addText(c.newText('Opening title'), 'Text');
    final content = c.movie.tracks.single.contents.single;
    expect(
      (content.kind, content.start, content.length, content.name),
      (TrackKind.text, 5, 20, 'Opening title'),
    );
    expect(c.textOf(content.id)!.alignment, TextAlignment.center);
    c.setText(content.id, c.textOf(content.id)!.copyWith(text: 'The end'));
    expect(c.content(content.id)!.name, 'The end');
    expect(c.textOf(content.id)!.text, 'The end');
    c.undo();
    expect(c.content(content.id)!.name, 'Opening title');

    ui.Image? image;
    await tester.runAsync(() async {
      for (var i = 0; i < 50 && image == null; i++) {
        image = c.frames.image(content, c.drawings[content.id]!, 10);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    final pixels = (await tester.runAsync(image!.toByteData))!.buffer
        .asUint8List();
    var inked = 0;
    for (var i = 3; i < pixels.length; i += 4) {
      if (pixels[i] > 0) inked++;
    }
    expect(inked, greaterThan(100), reason: 'the words are drawn');
  });

  testWidgets('add a Text track from the menu; a double tap edits it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = MemoryStorage();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MovieScreen(
          storage: storage,
          movie: film(),
          askName: (name) async => name,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timeline-add-track')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('text-content-words')),
      'Hello',
    );
    await tester.tap(find.byKey(const ValueKey('text-content-italic')));
    await tester.tap(find.byKey(const ValueKey('text-content-done')));
    await tester.pumpAndSettle();
    final content = storage.movies['m']!.tracks.single.contents.single;
    expect((content.kind, content.name), (TrackKind.text, 'Hello'));
    expect(
      storage.movieDrawings['m']![content.id]!.layers.single.text!.italic,
      isTrue,
    );

    final block = find.byKey(ValueKey('content-${content.id}'));
    await tester.tap(block);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(block);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('text-content-dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('text-content-words')),
      'Goodbye',
    );
    await tester.tap(find.byKey(const ValueKey('text-content-done')));
    await tester.pumpAndSettle();
    expect(storage.movies['m']!.tracks.single.contents.single.name, 'Goodbye');
    await tester.pumpWidget(const SizedBox());
  });
}
