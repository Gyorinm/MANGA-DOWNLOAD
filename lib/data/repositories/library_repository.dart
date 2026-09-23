import 'dart:async';

import '../../core/storage/file_storage.dart';
import '../../domain/entities/chapter.dart';
import '../../domain/entities/manga.dart';
import '../local/library_dao.dart';
import '../sources/source_registry.dart';

/// الواجهة الوحيدة التي تتعامل معها الشاشات.
class LibraryRepository {
  LibraryRepository({
    required LibraryDao dao,
    required SourceRegistry registry,
    required FileStorage storage,
  })  : _dao = dao,
        _registry = registry,
        _storage = storage;

  final LibraryDao _dao;
  final SourceRegistry _registry;
  final FileStorage _storage;
  final _libraryChanges = StreamController<void>.broadcast();

  Stream<void> get changes => _libraryChanges.stream;

  void notifyChanged() {
    if (!_libraryChanges.isClosed) _libraryChanges.add(null);
  }

  /// يبحث في كل المصادر المحددة ولا يخفي المصادر التي فشل طلبها.
  /// هذا يجعل المصدر ظاهرًا في الشاشة مع رسالة الخطأ بدل اختفائه بصمت.
  Future<List<SourceResults>> searchAll(String query,
      {Set<String>? sourceIds}) async {
    final selected = _registry.all
        .where((s) => sourceIds == null || sourceIds.contains(s.id));
    final futures = selected.map((source) async {
      try {
        final results = await source.search(query);
        return SourceResults(
          sourceId: source.id,
          sourceName: source.displayName,
          items: results,
          error: results.isEmpty ? 'لم يعثر هذا المصدر على نتائج.' : null,
        );
      } catch (e) {
        return SourceResults(
          sourceId: source.id,
          sourceName: source.displayName,
          items: const [],
          error: 'تعذّر البحث في هذا المصدر: ${e.toString()}',
        );
      }
    });
    return Future.wait(futures);
  }

  Future<Manga> mangaDetails(Manga stub) async {
    final local = await _dao.findManga(stub.key);
    if (local != null) return local;
    return _registry.require(stub.sourceId).details(stub.remoteId);
  }

  Future<List<Chapter>> chapters(Manga manga, {bool refresh = false}) async {
    final cached = await _dao.chaptersOf(manga.key);
    if (!refresh && cached.isNotEmpty) return cached;
    try {
      final fresh = await _registry.require(manga.sourceId).chapters(manga.remoteId);
      if (await _dao.findManga(manga.key) != null) {
        await _dao.mergeChapters(manga.key, fresh);
        return _dao.chaptersOf(manga.key);
      }
      return fresh;
    } catch (_) {
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<List<Chapter>> localChapters(String mangaKey) => _dao.chaptersOf(mangaKey);
  Future<List<Manga>> library() => _dao.libraryManga();
  Future<Manga?> findLocal(String mangaKey) => _dao.findManga(mangaKey);

  Future<Manga> addToLibrary(Manga manga, List<Chapter> chapters) async {
    final entry = manga.copyWith(
      totalChapters: chapters.length,
      addedAt: manga.addedAt ?? DateTime.now(),
    );
    await _dao.upsertManga(entry);
    await _dao.mergeChapters(entry.key, chapters);
    notifyChanged();
    return (await _dao.findManga(entry.key)) ?? entry;
  }

  Future<void> markOpened(String mangaKey) async {
    await _dao.touchManga(mangaKey);
    notifyChanged();
  }

  Future<void> saveReadingPosition(String chapterKey, int page) =>
      _dao.saveReadingPosition(chapterKey, page);

  Future<void> removeManga(String mangaKey) async {
    await _dao.deleteManga(mangaKey);
    await _storage.deleteManga(mangaKey);
    notifyChanged();
  }

  Future<void> removeChapterFiles(Chapter chapter) async {
    await _storage.deleteChapter(chapter.mangaKey, chapter.remoteId);
    await _dao.resetChapter(chapter.key);
    notifyChanged();
  }

  Future<int> mangaSizeOnDisk(String mangaKey) =>
      _storage.sizeOf(_storage.mangaDir(mangaKey));

  Future<int> totalSizeOnDisk() async {
    var total = 0;
    for (final m in await _dao.libraryManga()) {
      total += await mangaSizeOnDisk(m.key);
    }
    return total;
  }

  void dispose() => _libraryChanges.close();
}

class SourceResults {
  const SourceResults({
    required this.sourceId,
    required this.sourceName,
    required this.items,
    this.error,
  });

  final String sourceId;
  final String sourceName;
  final List<Manga> items;
  final String? error;
}
