import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import '../domain/document.dart';
import '../domain/movie.dart';

/// Gallery contents. Unreadable archives are reported, never fatal.
class GalleryListing {
  const GalleryListing(this.documents, [this.unreadable = const []]);
  final List<ArtDocument> documents;

  /// File names of archives that neither the main copy nor a recovery copy
  /// could restore. They are left untouched on disk.
  final List<String> unreadable;
}

abstract interface class StudioStorage {
  Future<ArtDocument?> loadDocument();
  Future<void> saveDocument(ArtDocument document);
  Future<Map<String, dynamic>?> loadLibrary();
  Future<void> saveLibrary(Map<String, dynamic> library);

  /// Gallery drawings, most recently saved first.
  Future<GalleryListing> listDocuments();

  /// Saves [document] in the gallery only, not as the open drawing.
  Future<void> saveToGallery(ArtDocument document);

  /// Removes drawing [id] from the gallery for good.
  Future<void> deleteDocument(String id);

  /// The gallery's order and stacks.
  Future<Map<String, dynamic>?> loadGallery();
  Future<void> saveGallery(Map<String, dynamic> gallery);

  /// Frees storage no saved drawing refers to any more.
  Future<void> compact();

  /// Theater movies, most recently saved first.
  Future<MovieListing> listMovies();

  /// [drawings] (by content id) are written with the movie; without them
  /// the movie keeps the drawings it has.
  Future<void> saveMovie(
    MovieDocument movie, {
    Map<String, ArtDocument>? drawings,
  });

  /// The drawings inside movie [id], by content id.
  Future<Map<String, ArtDocument>> loadMovieDrawings(String id);

  /// Removes movie [id] for good.
  Future<void> deleteMovie(String id);

  /// When movie [id]'s recovery points were kept, newest first.
  Future<List<DateTime>> moviePoints(String id);

  /// Movie [id] back as it was at recovery point [at]; false when that
  /// point is gone.
  Future<bool> restoreMoviePoint(String id, DateTime at);

  /// The file at [sourcePath] copied into the movies' media; its id.
  Future<String> importMedia(String sourcePath);

  /// Where media [id] is, or null when it is gone.
  Future<String?> mediaPath(String id);

  /// The Theater's order and folders.
  Future<Map<String, dynamic>?> loadTheater();
  Future<void> saveTheater(Map<String, dynamic> theater);
}

/// Theater contents. Unreadable movie files are reported, never fatal.
class MovieListing {
  const MovieListing(this.movies, [this.unreadable = const []]);
  final List<MovieDocument> movies;
  final List<String> unreadable;
}

/// Temporary-file commit with a previous complete revision kept for recovery.
/// The write queue must be shared by all writes to a particular file.
///
/// Crash points: before promotion the main file is intact; between moving
/// the main file to `.bak` and promoting `.tmp`, `.tmp` is the newest complete
/// copy and [read] restores it. A failed temp write (e.g. a full disk) removes
/// the partial `.tmp` and leaves the main file untouched.
class AtomicJsonFile {
  AtomicJsonFile(this.file);
  final File file;
  Future<void> _tail = Future.value();
  bool recovered = false;
  static const maxBytes = 32 * 1024 * 1024;

  /// Fault injection: called with `temp` after the temporary file is written
  /// and with `promote` right before it replaces the main file.
  @visibleForTesting
  Future<void> Function(String step)? fault;

  Future<Map<String, dynamic>?> read() => readAs((json) => json);

  /// Main, `.tmp` and `.bak`: every complete copy that may be read back.
  List<File> get copies => [
    file,
    File('${file.path}.tmp'),
    File('${file.path}.bak'),
  ];

  /// The first of main, `.tmp`, `.bak` that decodes and that [parse] accepts.
  Future<T?> readAs<T>(FutureOr<T> Function(Map<String, dynamic>) parse) async {
    Object? failure;
    for (final candidate in copies) {
      if (!await candidate.exists()) continue;
      try {
        if (await candidate.length() > maxBytes) {
          throw const FormatException('File exceeds size limit');
        }
        final value = jsonDecode(await candidate.readAsString());
        if (value is! Map<String, dynamic>) {
          throw const FormatException('Expected JSON object');
        }
        final parsed = await parse(value);
        recovered = candidate.path != file.path;
        if (candidate.path.endsWith('.tmp') && !await file.exists()) {
          // Interrupted between moving main to .bak and promoting .tmp: finish
          // the promotion so the next write cannot overwrite the only copy.
          await candidate.rename(file.path);
          recovered = false;
        }
        return parsed;
      } catch (error) {
        failure = error;
      }
    }
    if (failure != null) {
      throw FormatException('Cannot recover saved data: $failure');
    }
    return null;
  }

  /// UTF-8 JSON, encoded on a background isolate: a large document takes
  /// long enough to drop frames while the user is drawing. [value] must be
  /// sendable; use `toJson(deferPng: true)` so base64 also happens there.
  static Future<Uint8List> encode(Map<String, dynamic> value) =>
      Isolate.run(() => utf8.encode(jsonEncode(value)));

  Future<void> write(Map<String, dynamic> value) => writeEncoded(encode(value));

  /// Writes are applied in call order even when encodings finish out of order.
  Future<void> writeEncoded(Future<Uint8List> encoded) {
    final operation = _tail.then((_) async {
      final bytes = await encoded;
      if (bytes.length > maxBytes) {
        throw const FormatException('Document exceeds storage limit');
      }
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      final backup = File('${file.path}.bak');
      try {
        await temp.writeAsBytes(bytes, flush: true);
        await fault?.call('temp');
      } catch (_) {
        // Do not leave a partial copy behind, e.g. on a full disk.
        try {
          if (await temp.exists()) await temp.delete();
        } catch (_) {}
        rethrow;
      }
      if (await file.exists() && !recovered) {
        // Keep the last complete main file. A failed promotion still leaves backup.
        if (await backup.exists()) await backup.delete();
        await file.rename(backup.path);
      }
      await fault?.call('promote');
      await temp.rename(file.path);
      recovered = false;
    });
    _tail = operation.catchError((Object _) {});
    return operation;
  }
}

/// Content-addressed PNG tiles shared by every saved drawing: one file per
/// SHA-256, written once (temp file, then rename) before any manifest refers
/// to it. Unchanged tiles are never written again.
class TileStore {
  TileStore(this.directory);
  final Directory directory;
  Set<String>? _known;

  static final _digest = RegExp(r'^[0-9a-f]{64}$');
  File _file(String digest) => File('${directory.path}/$digest.png');

  Future<Set<String>> _scan() async {
    final known = _known;
    if (known != null) return known;
    final found = <String>{};
    if (await directory.exists()) {
      await for (final entry in directory.list()) {
        final name = entry.uri.pathSegments.last;
        if (entry is File && name.endsWith('.png')) {
          found.add(name.substring(0, name.length - 4));
        }
      }
    }
    return _known = found;
  }

  Future<void> write(Map<String, Uint8List> blobs) async {
    final known = await _scan();
    final missing = blobs.keys.where((d) => !known.contains(d)).toList();
    if (missing.isEmpty) return;
    await directory.create(recursive: true);
    for (final digest in missing) {
      if (!_digest.hasMatch(digest)) throw const FormatException('Bad tile');
      final file = _file(digest), temp = File('${file.path}.tmp');
      try {
        await temp.writeAsBytes(blobs[digest]!, flush: true);
        await temp.rename(file.path);
      } catch (_) {
        try {
          if (await temp.exists()) await temp.delete();
        } catch (_) {}
        rethrow;
      }
      known.add(digest);
    }
  }

  /// The tiles that exist and still match their digest; others are absent.
  Future<Map<String, Uint8List>> read(Set<String> digests) async {
    final blobs = <String, Uint8List>{};
    for (final digest in digests) {
      if (!_digest.hasMatch(digest)) continue;
      final file = _file(digest);
      if (await file.exists()) blobs[digest] = await file.readAsBytes();
    }
    if (blobs.isEmpty) return blobs;
    return Isolate.run(() => verifiedBlobs(blobs));
  }

  /// Deletes every tile outside [keep] and any interrupted temp file.
  Future<int> retainOnly(Set<String> keep) async {
    if (!await directory.exists()) return 0;
    var removed = 0;
    await for (final entry in directory.list()) {
      final name = entry.uri.pathSegments.last;
      final stale =
          name.endsWith('.tmp') ||
          (name.endsWith('.png') &&
              !keep.contains(name.substring(0, name.length - 4)));
      if (entry is File && stale) {
        await entry.delete();
        removed++;
      }
    }
    _known = null;
    return removed;
  }
}

/// Drawings as small JSON manifests (current + one archive per drawing)
/// whose raster tiles live in a shared [TileStore]. A save writes missing
/// tiles first and then swaps each manifest atomically, so every manifest on
/// disk only refers to complete tiles.
class LocalStudioStorage implements StudioStorage {
  LocalStudioStorage(Directory directory)
    : documentsDirectory = Directory('${directory.path}/documents'),
      tiles = TileStore(Directory('${directory.path}/tiles')),
      documentFile = AtomicJsonFile(File('${directory.path}/current.artdoc')),
      libraryFile = AtomicJsonFile(File('${directory.path}/library.json')),
      galleryFile = AtomicJsonFile(File('${directory.path}/gallery.json')),
      moviesDirectory = Directory('${directory.path}/movies'),
      mediaDirectory = Directory('${directory.path}/media'),
      theaterFile = AtomicJsonFile(File('${directory.path}/theater.json'));
  final Directory documentsDirectory, moviesDirectory, mediaDirectory;
  final AtomicJsonFile theaterFile;
  final Map<String, AtomicJsonFile> _movies = {};
  final TileStore tiles;
  final Map<String, AtomicJsonFile> _documents = {};
  final AtomicJsonFile documentFile, libraryFile, galleryFile;

  /// Saves and compaction never overlap: compaction must not see a tile
  /// written for a manifest that is not on disk yet.
  Future<void> _queue = Future.value();
  int _savesSinceCompact = 0;
  static const compactEvery = 64;

  static Future<LocalStudioStorage> create() async {
    final directory = await getApplicationSupportDirectory();
    return LocalStudioStorage(Directory('${directory.path}/studio-v1'));
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  AtomicJsonFile archive(String documentId) {
    final id = base64Url.encode(utf8.encode(documentId));
    return _documents.putIfAbsent(
      id,
      () => AtomicJsonFile(File('${documentsDirectory.path}/$id.artdoc')),
    );
  }

  /// A manifest whose tiles are missing or damaged fails like invalid JSON,
  /// so reading falls through to the next recovery copy.
  Future<ArtDocument> _parse(Map<String, dynamic> json) async =>
      ArtDocument.fromJson(
        json,
        blobs: await tiles.read(referencedBlobs(json)),
      );

  @override
  Future<ArtDocument?> loadDocument() => documentFile.readAs(_parse);

  Future<Uint8List> _encode(ArtDocument document) async {
    await RasterAsset.hashAll([
      for (final layer in document.layers) ...?layer.raster?.tiles.values,
    ]);
    final blobs = <String, Uint8List>{};
    final manifest = document.toJson(deferPng: true, blobs: blobs);
    await tiles.write(blobs);
    return AtomicJsonFile.encode(manifest);
  }

  @override
  Future<void> saveDocument(ArtDocument document) => _serial(() async {
    final encoded = Future.value(await _encode(document));
    // The current file first: if the archive write is interrupted, the next
    // launch still opens this snapshot and its next save repairs the archive.
    await documentFile.writeEncoded(encoded);
    await archive(document.id).writeEncoded(encoded);
    if (++_savesSinceCompact >= compactEvery) await _compact();
  });

  @override
  Future<void> saveToGallery(ArtDocument document) => _serial(() async {
    await archive(document.id)
        .writeEncoded(Future.value(await _encode(document)));
  });

  @override
  Future<void> deleteDocument(String id) => _serial(() async {
    for (final copy in archive(id).copies) {
      if (await copy.exists()) await copy.delete();
    }
    _documents.remove(base64Url.encode(utf8.encode(id)));
    await _compact();
  });

  @override
  Future<Map<String, dynamic>?> loadGallery() => galleryFile.read();
  @override
  Future<void> saveGallery(Map<String, dynamic> gallery) =>
      galleryFile.write(gallery);

  @override
  Future<void> compact() => _serial(_compact);

  AtomicJsonFile movieFile(String movieId) {
    final id = base64Url.encode(utf8.encode(movieId));
    return _movies.putIfAbsent(
      id,
      () => AtomicJsonFile(File('${moviesDirectory.path}/$id.movie')),
    );
  }

  /// Each movie's drawings as last written (manifests, tiles stored).
  final Map<String, Map<String, dynamic>> _drawingManifests = {};

  Future<Map<String, dynamic>> _storedDrawings(String movieId) async =>
      _drawingManifests[movieId] ??= switch (await movieFile(movieId).read()) {
        {'drawings': final Map<String, dynamic> drawings} => drawings,
        _ => <String, dynamic>{},
      };

  @override
  Future<void> saveMovie(
    MovieDocument movie, {
    Map<String, ArtDocument>? drawings,
  }) => _serial(() async {
    final Map<String, dynamic> manifests;
    if (drawings == null) {
      manifests = await _storedDrawings(movie.id);
    } else {
      final blobs = <String, Uint8List>{};
      await RasterAsset.hashAll([
        for (final d in drawings.values)
          for (final layer in d.layers) ...?layer.raster?.tiles.values,
      ]);
      manifests = {
        for (final MapEntry(:key, :value) in drawings.entries)
          key: value.toJson(deferPng: true, blobs: blobs),
      };
      await tiles.write(blobs);
      _drawingManifests[movie.id] = manifests;
    }
    final json = {
      ...movie.toJson(),
      if (manifests.isNotEmpty) 'drawings': manifests,
    };
    await movieFile(movie.id).write(json);
    await _keepPoint(movie.id, json);
  });

  /// How often, at most, a movie's recovery point is kept, and how many.
  static const pointEvery = Duration(minutes: 5), pointsKept = 10;
  final Map<String, DateTime> _lastPoint = {};

  Directory _points(String movieId) => Directory(
    '${moviesDirectory.path}/${base64Url.encode(utf8.encode(movieId))}.points',
  );

  Future<void> _keepPoint(String movieId, Map<String, dynamic> json) async {
    final now = DateTime.now();
    final dir = _points(movieId);
    var last = _lastPoint[movieId];
    if (last == null && await dir.exists()) {
      final points = await moviePoints(movieId);
      last = points.firstOrNull;
    }
    if (last != null && now.difference(last) < pointEvery) return;
    _lastPoint[movieId] = now;
    await dir.create(recursive: true);
    await File('${dir.path}/${now.millisecondsSinceEpoch}.movie')
        .writeAsBytes(await AtomicJsonFile.encode(json), flush: true);
    final points = await moviePoints(movieId);
    for (final old in points.skip(pointsKept)) {
      await File('${dir.path}/${old.millisecondsSinceEpoch}.movie').delete();
    }
  }

  @override
  Future<List<DateTime>> moviePoints(String id) async {
    final dir = _points(id);
    if (!await dir.exists()) return const [];
    final times = <DateTime>[
      await for (final e in dir.list())
        if (e is File && e.path.endsWith('.movie'))
          if (int.tryParse(e.uri.pathSegments.last.split('.').first)
              case final ms?)
            DateTime.fromMillisecondsSinceEpoch(ms),
    ]..sort((a, b) => b.compareTo(a));
    return times;
  }

  @override
  Future<bool> restoreMoviePoint(String id, DateTime at) => _serial(() async {
    final file = File('${_points(id).path}/${at.millisecondsSinceEpoch}.movie');
    if (!await file.exists()) return false;
    final json = jsonDecode(await file.readAsString());
    if (json is! Map<String, dynamic>) return false;
    MovieDocument.fromJson(json);
    await movieFile(id).write(json);
    _drawingManifests.remove(id);
    return true;
  });

  @override
  Future<Map<String, ArtDocument>> loadMovieDrawings(String id) async {
    final stored = await _storedDrawings(id);
    return {
      for (final MapEntry(:key, :value) in stored.entries)
        if (value is Map<String, dynamic>) key: await _parse(value),
    };
  }

  @override
  Future<void> deleteMovie(String id) => _serial(() async {
    for (final copy in movieFile(id).copies) {
      if (await copy.exists()) await copy.delete();
    }
    if (await _points(id).exists()) await _points(id).delete(recursive: true);
    _movies.remove(base64Url.encode(utf8.encode(id)));
    _drawingManifests.remove(id);
    await _compact();
  });

  @override
  Future<MovieListing> listMovies() async {
    if (!await moviesDirectory.exists()) return const MovieListing([]);
    final files = await moviesDirectory
        .list()
        .where((e) => e is File && e.path.endsWith('.movie'))
        .cast<File>()
        .toList();
    final movies = <(DateTime, MovieDocument)>[];
    final unreadable = <String>[];
    for (final entry in files) {
      try {
        final movie = await AtomicJsonFile(entry)
            .readAs(MovieDocument.fromJson);
        if (movie != null) movies.add((await entry.lastModified(), movie));
      } catch (_) {
        unreadable.add(entry.uri.pathSegments.last);
      }
    }
    movies.sort((a, b) => b.$1.compareTo(a.$1));
    return MovieListing([for (final (_, m) in movies) m], unreadable);
  }

  /// Media brought in this session: not swept before a movie refers to it.
  final _freshMedia = <String>{};

  @override
  Future<String> importMedia(String sourcePath) async {
    await mediaDirectory.create(recursive: true);
    final dot = sourcePath.lastIndexOf('.');
    final ext = dot < 0 ? '' : sourcePath.substring(dot + 1).toLowerCase();
    final id = '${newId()}${ext.isEmpty || ext.length > 5 ? '' : '.$ext'}';
    _freshMedia.add(id);
    await File(sourcePath).copy('${mediaDirectory.path}/$id');
    return id;
  }

  @override
  Future<String?> mediaPath(String id) async {
    if (id.contains('/') || id.contains('..')) return null;
    final file = File('${mediaDirectory.path}/$id');
    return await file.exists() ? file.path : null;
  }

  @override
  Future<Map<String, dynamic>?> loadTheater() => theaterFile.read();
  @override
  Future<void> saveTheater(Map<String, dynamic> theater) =>
      theaterFile.write(theater);

  /// Removes tiles no manifest copy refers to (`.tmp` and `.bak` included,
  /// they are recovery points). Any manifest that cannot be read keeps
  /// everything: its tiles are unknown.
  Future<void> _compact() async {
    _savesSinceCompact = 0;
    final keep = <String>{};
    final copy = RegExp(r'\.(artdoc|movie)(\.tmp|\.bak)?$');
    final manifests = [
      ...documentFile.copies,
      // Every copy on its own: an interrupted save may leave only `.tmp`
      // or `.bak` of an archive.
      if (await documentsDirectory.exists())
        ...await documentsDirectory
            .list()
            .where((e) => e is File && copy.hasMatch(e.path))
            .cast<File>()
            .toList(),
      // Movies hold drawings too, their recovery points as well.
      if (await moviesDirectory.exists())
        ...await moviesDirectory
            .list(recursive: true)
            .where((e) => e is File && copy.hasMatch(e.path))
            .cast<File>()
            .toList(),
    ];
    final media = <String>{};
    void mediaIds(Object? json) {
      if (json is Map) {
        if (json['mediaId'] case final String id) media.add(id);
        json.values.forEach(mediaIds);
      } else if (json is List) {
        json.forEach(mediaIds);
      }
    }

    for (final file in manifests) {
      if (!await file.exists()) continue;
      try {
        final json = jsonDecode(await file.readAsString());
        if (json is! Map<String, dynamic>) return;
        mediaIds(json);
        keep.addAll(
          file.path.contains('.movie')
              ? movieReferencedBlobs(json)
              : referencedBlobs(json),
        );
      } catch (_) {
        return;
      }
    }
    await tiles.retainOnly(keep);
    if (await mediaDirectory.exists()) {
      await for (final entry in mediaDirectory.list()) {
        final name = entry.uri.pathSegments.last;
        if (entry is File &&
            !media.contains(name) &&
            !_freshMedia.contains(name)) {
          await entry.delete();
        }
      }
    }
  }

  @override
  Future<GalleryListing> listDocuments() async {
    if (!await documentsDirectory.exists()) return const GalleryListing([]);
    final files = await documentsDirectory
        .list()
        .where((e) => e is File && e.path.endsWith('.artdoc'))
        .cast<File>()
        .toList();
    final documents = <(DateTime, ArtDocument)>[];
    final unreadable = <String>[];
    for (final entry in files) {
      try {
        final document = await AtomicJsonFile(entry).readAs(_parse);
        if (document != null) {
          documents.add((await entry.lastModified(), document));
        }
      } catch (_) {
        unreadable.add(entry.uri.pathSegments.last);
      }
    }
    documents.sort((a, b) => b.$1.compareTo(a.$1));
    return GalleryListing([for (final (_, d) in documents) d], unreadable);
  }

  @override
  Future<Map<String, dynamic>?> loadLibrary() => libraryFile.read();
  @override
  Future<void> saveLibrary(Map<String, dynamic> library) =>
      libraryFile.write(library);
}
