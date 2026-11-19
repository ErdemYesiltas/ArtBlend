import 'package:atelier_studio/data/studio_storage.dart';
import 'package:atelier_studio/domain/document.dart';
import 'package:atelier_studio/domain/movie.dart';

class MemoryStorage implements StudioStorage {
  ArtDocument? document;
  Map<String, dynamic>? library;
  final Map<String, ArtDocument> documents = {};
  @override
  Future<ArtDocument?> loadDocument() async => document;
  @override
  Future<Map<String, dynamic>?> loadLibrary() async => library;
  @override
  Future<void> saveDocument(ArtDocument value) async {
    document = value;
    documents.remove(value.id);
    documents[value.id] = value;
  }

  @override
  Future<GalleryListing> listDocuments() async =>
      GalleryListing(documents.values.toList().reversed.toList());

  @override
  Future<void> compact() async {}

  @override
  Future<void> saveLibrary(Map<String, dynamic> value) async {
    library = value;
  }

  Map<String, dynamic>? gallery;

  @override
  Future<void> saveToGallery(ArtDocument value) async {
    documents.remove(value.id);
    documents[value.id] = value;
  }

  @override
  Future<void> deleteDocument(String id) async {
    documents.remove(id);
  }

  final Map<String, MovieDocument> movies = {};
  Map<String, dynamic>? theater;

  @override
  Future<MovieListing> listMovies() async =>
      MovieListing(movies.values.toList().reversed.toList());

  final Map<String, Map<String, ArtDocument>> movieDrawings = {};

  @override
  Future<void> saveMovie(
    MovieDocument value, {
    Map<String, ArtDocument>? drawings,
  }) async {
    movies.remove(value.id);
    movies[value.id] = value;
    if (drawings != null) movieDrawings[value.id] = {...drawings};
  }

  @override
  Future<Map<String, ArtDocument>> loadMovieDrawings(String id) async => {
    ...?movieDrawings[id],
  };

  @override
  Future<void> deleteMovie(String id) async {
    movies.remove(id);
    movieDrawings.remove(id);
  }

  final Map<String, String> media = {};

  @override
  Future<String> importMedia(String sourcePath) async {
    final id = 'media${media.length}';
    media[id] = sourcePath;
    return id;
  }

  @override
  Future<String?> mediaPath(String id) async => media[id];

  @override
  Future<List<DateTime>> moviePoints(String id) async => const [];
  @override
  Future<bool> restoreMoviePoint(String id, DateTime at) async => false;

  @override
  Future<Map<String, dynamic>?> loadTheater() async => theater;

  @override
  Future<void> saveTheater(Map<String, dynamic> value) async {
    theater = value;
  }

  @override
  Future<Map<String, dynamic>?> loadGallery() async => gallery;

  @override
  Future<void> saveGallery(Map<String, dynamic> value) async {
    gallery = value;
  }
}
