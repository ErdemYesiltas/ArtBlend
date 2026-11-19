import 'package:atelier_studio/editor/editor_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('picked files are checked by extension after an unfiltered pick', () {
    const documents = ['artdoc', 'json'];
    requireExtension('Sketch.ARTDOC', documents);
    requireExtension('old.json', documents);
    expect(
      () => requireExtension('photo.png', documents),
      throwsA(isA<UnsupportedFile>()),
    );
    expect(
      () => requireExtension('artdoc', documents),
      throwsA(isA<UnsupportedFile>()),
    );
  });
}
