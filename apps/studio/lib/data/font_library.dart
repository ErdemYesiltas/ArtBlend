import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Fonts the user imported (TTF, OTF, TTC), kept in the app's support
/// folder and loaded on every start. A font's family is its file name.
class FontLibrary {
  FontLibrary(this.directory);
  final Directory directory;

  static const extensions = ['ttf', 'otf', 'ttc'];
  static const maxBytes = 40 * 1024 * 1024;

  static Future<FontLibrary> open() async => FontLibrary(
    Directory('${(await getApplicationSupportDirectory()).path}/fonts'),
  );

  static String familyOf(String fileName) {
    final base = fileName.split(RegExp(r'[/\\]')).last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }

  static bool accepts(String fileName) =>
      extensions.contains(fileName.split('.').last.toLowerCase());

  /// Every saved font: its family and bytes.
  Future<List<(String, Uint8List)>> load() async {
    if (!await directory.exists()) return const [];
    final fonts = <(String, Uint8List)>[];
    await for (final entry in directory.list()) {
      if (entry is! File || !accepts(entry.path)) continue;
      fonts.add((familyOf(entry.path), await entry.readAsBytes()));
    }
    fonts.sort((a, b) => a.$1.toLowerCase().compareTo(b.$1.toLowerCase()));
    return fonts;
  }

  /// Saves a font file; its family.
  Future<String> add(String fileName, Uint8List bytes) async {
    if (!accepts(fileName)) {
      throw const FormatException('Not a TTF, OTF or TTC font');
    }
    if (bytes.length > maxBytes) throw const FormatException('Font too large');
    await directory.create(recursive: true);
    final name = fileName.split(RegExp(r'[/\\]')).last;
    await File('${directory.path}/$name').writeAsBytes(bytes, flush: true);
    return familyOf(name);
  }
}
