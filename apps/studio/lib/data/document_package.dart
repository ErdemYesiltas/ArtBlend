import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../domain/document.dart';

/// Largest drawing file accepted for opening, packed or not.
const maxDocumentFileBytes = 64 * 1024 * 1024;

/// Largest unpacked content a package may expand to (zip-bomb bound).
const maxPackageContentBytes = 128 * 1024 * 1024;

/// A drawing as one portable `.artdoc` file: a zip holding `manifest.json`
/// and `tiles/<sha256>.png`, the same layout the app stores internally.
/// PNGs are stored as they are; they are already compressed. Pass the
/// manifest from `toJson(blobs:)` with its blobs; runs on any isolate.
Uint8List encodeDocumentPackage(
  (Map<String, dynamic>, Map<String, Uint8List>) parts,
) {
  final (manifest, blobs) = parts;
  final archive = Archive()
    ..addFile(
      ArchiveFile.bytes('manifest.json', utf8.encode(jsonEncode(manifest))),
    );
  for (final MapEntry(:key, :value) in blobs.entries) {
    archive.addFile(
      ArchiveFile.noCompress('tiles/$key.png', value.length, value),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

bool _isZip(Uint8List bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x50 &&
    bytes[1] == 0x4b &&
    bytes[2] == 3 &&
    bytes[3] == 4;

/// Opens a `.artdoc` package, or a single-JSON drawing written by earlier
/// versions. Every tile must match its digest. Runs on any isolate.
ArtDocument decodeDocumentFile(Uint8List bytes) {
  if (bytes.length > maxDocumentFileBytes) {
    throw const FormatException('File too large');
  }
  if (!_isZip(bytes)) {
    return ArtDocument.fromJson(
      Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map),
    );
  }
  final archive = ZipDecoder().decodeBytes(bytes);
  var unpacked = 0;
  Uint8List read(ArchiveFile file, int limit) {
    unpacked += file.size;
    if (file.size > limit || unpacked > maxPackageContentBytes) {
      throw const FormatException('Package content exceeds size limit');
    }
    return file.content;
  }

  final manifestFile = archive.findFile('manifest.json');
  if (manifestFile == null) {
    throw const FormatException('Not an ArtBlend drawing package');
  }
  final json = Map<String, dynamic>.from(
    jsonDecode(utf8.decode(read(manifestFile, 32 * 1024 * 1024))) as Map,
  );
  final blobs = <String, Uint8List>{};
  for (final digest in referencedBlobs(json)) {
    final tile = archive.findFile('tiles/$digest.png');
    if (tile != null) blobs[digest] = read(tile, RasterAsset.maxBytes);
  }
  return ArtDocument.fromJson(json, blobs: verifiedBlobs(blobs));
}
