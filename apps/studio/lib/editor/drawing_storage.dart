import '../data/studio_storage.dart';
import '../domain/document.dart';
import '../domain/movie.dart';

/// Storage for the editor opened on a drawing inside a movie: it reads
/// and writes only that drawing (to [onSave]) and shares the brush and
/// palette library with [base]. The gallery and the Theater are out of
/// reach from there, so nothing else can be written over the drawing.
class DrawingStorage implements StudioStorage {
  DrawingStorage(this.base, this.drawing, this.onSave);
  final StudioStorage base;
  final ArtDocument drawing;
  final void Function(ArtDocument drawing) onSave;

  @override
  Future<ArtDocument?> loadDocument() async => drawing;

  /// Only the drawing it opened: a document opened or made in its place
  /// is never saved over it.
  @override
  Future<void> saveDocument(ArtDocument document) async {
    if (document.id == drawing.id) onSave(document);
  }

  @override
  Future<Map<String, dynamic>?> loadLibrary() => base.loadLibrary();
  @override
  Future<void> saveLibrary(Map<String, dynamic> library) =>
      base.saveLibrary(library);

  @override
  Future<GalleryListing> listDocuments() async => const GalleryListing([]);
  @override
  Future<void> saveToGallery(ArtDocument document) async {}
  @override
  Future<void> deleteDocument(String id) async {}
  @override
  Future<Map<String, dynamic>?> loadGallery() async => null;
  @override
  Future<void> saveGallery(Map<String, dynamic> gallery) async {}

  /// The movie's storage compacts; tiles of a drawing being edited are not
  /// on disk yet.
  @override
  Future<void> compact() async {}

  @override
  Future<MovieListing> listMovies() async => const MovieListing([]);
  @override
  Future<void> saveMovie(
    MovieDocument movie, {
    Map<String, ArtDocument>? drawings,
  }) async {}
  @override
  Future<Map<String, ArtDocument>> loadMovieDrawings(String id) async => {};
  @override
  Future<void> deleteMovie(String id) async {}
  @override
  Future<String> importMedia(String sourcePath) => base.importMedia(sourcePath);
  @override
  Future<String?> mediaPath(String id) => base.mediaPath(id);
  @override
  Future<List<DateTime>> moviePoints(String id) async => const [];
  @override
  Future<bool> restoreMoviePoint(String id, DateTime at) async => false;
  @override
  Future<Map<String, dynamic>?> loadTheater() async => null;
  @override
  Future<void> saveTheater(Map<String, dynamic> theater) async {}
}
