import 'dart:async';

import '../../core/storage/file_storage.dart';
import '../../domain/entities/chapter.dart';
import '../../domain/entities/manga.dart';
import '../local/library_dao.dart';
import '../sources/source_registry.dart';

/// الواجهة الوحيدة التي تتعامل معها الشاشات.
///
/// تُخفي عن الواجهة من أين جاءت البيانات: من الشبكة أم من القرص.
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

  /// إشارة «تغيّرت المكتبة» تستمع إليها الشاشات لتعيد الجلب.
  Stream<void> get changes => _libraryChanges.stream;

  void notifyChanged() {
    if (!_libraryChanges.isClosed) _libraryChanges.add(null);
  }

  // ── بحث عبر كل المصادر ────────────────────────────────────────────────

  /// يبحث في المصادر المختارة بالتوازي ([sourceIds]، وnull تعني الكل).
  /// فشل مصدر لا يُسقط البقية.
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
        );
      } catch (e) {
        return SourceResults(
          sourceId: source.id,
          sourceName: source.displayName,
          items: const [],
          error: 'تعذّر البحث في هذا المصدر.',
        );
      }
    });

    final all = await Future.wait(futures);
    // نُظهر المصدر فقط إذا وُجدت نتائج؛ الأخطاء والقوائم الفارغة تُخفى.
    return all.where((r) => r.items.isNotEmpty).toList();
  }

  // ── التفاصيل والفصول ──────────────────────────────────────────────────

  Future<Manga> mangaDetails(Manga stub) async {
    final local = await _dao.findManga(stub.key);
    if (local != null) return local;

    final source = _registry.require(stub.sourceId);
    final fresh = await source.details(stub.remoteId);
    return fresh;
  }

  /// يجلب الفصول من الشبكة عند الإمكان، ويسقط إلى النسخة المحلية عند تعذّرها.
  Future<List<Chapter>> chapters(Manga manga, {bool refresh = false}) async {
    final cached = await _dao.chaptersOf(manga.key);
    if (!refresh && cached.isNotEmpty) return cached;

    try {
      final source = _registry.require(manga.sourceId);
      final fresh = await source.chapters(manga.remoteId);
      if (await _dao.findManga(manga.key) != null) {
        await _dao.mergeChapters(manga.key, fresh);
        return await _dao.chaptersOf(manga.key);
      }
      return fresh;
    } catch (_) {
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<List<Chapter>> localChapters(String mangaKey) =>
      _dao.chaptersOf(mangaKey);

  // ── المكتبة المحلية ───────────────────────────────────────────────────

  Future<List<Manga>> library() => _dao.libraryManga();

  Future<Manga?> findLocal(String mangaKey) => _dao.findManga(mangaKey);

  /// يُضيف المانهوا إلى المكتبة مع فصولها. يُستدعى قبل بدء التحميل.
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

  /// حذف كامل: السجلات والملفات معًا، فلا تبقى بيانات يتيمة.
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

/// نتائج مصدر واحد داخل شاشة البحث.
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
