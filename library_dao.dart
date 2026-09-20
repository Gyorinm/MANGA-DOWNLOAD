import 'package:sqflite/sqflite.dart';

import '../../domain/entities/chapter.dart';
import '../../domain/entities/manga.dart';
import 'app_database.dart';

/// كل جملة SQL في التطبيق تعيش هنا. لا تسرّب هذه الطبقة أي `Map` إلى الخارج.
class LibraryDao {
  LibraryDao(this._db);

  final AppDatabase _db;

  Database get _raw => _db.db;

  // ── المانهوا ──────────────────────────────────────────────────────────

  Future<void> upsertManga(Manga manga) async {
    await _raw.insert(
      AppDatabase.tableManga,
      {
        'manga_key': manga.key,
        'source_id': manga.sourceId,
        'remote_id': manga.remoteId,
        'title': manga.title,
        'description': manga.description,
        'author': manga.author,
        'status': manga.status,
        'remote_cover_url': manga.remoteCoverUrl,
        'local_cover_path': manga.localCoverPath,
        'total_chapters': manga.totalChapters,
        'added_at':
            (manga.addedAt ?? DateTime.now()).millisecondsSinceEpoch,
        'last_opened_at': manga.lastOpenedAt?.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> setLocalCover(String mangaKey, String path) =>
      _raw.update(AppDatabase.tableManga, {'local_cover_path': path},
          where: 'manga_key = ?', whereArgs: [mangaKey]);

  Future<void> touchManga(String mangaKey) =>
      _raw.update(
        AppDatabase.tableManga,
        {'last_opened_at': DateTime.now().millisecondsSinceEpoch},
        where: 'manga_key = ?',
        whereArgs: [mangaKey],
      );

  Future<void> deleteManga(String mangaKey) => _raw.delete(
        AppDatabase.tableManga,
        where: 'manga_key = ?',
        whereArgs: [mangaKey],
      );

  Future<Manga?> findManga(String mangaKey) async {
    final rows = await _raw.query(
      AppDatabase.tableManga,
      where: 'manga_key = ?',
      whereArgs: [mangaKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mangaFromRow(rows.first, await _downloadedCount(mangaKey));
  }

  /// المكتبة مرتّبة بآخر فتح ثم بالإضافة — أقرب ما يكون لسلوك القارئ.
  Future<List<Manga>> libraryManga() async {
    final rows = await _raw.rawQuery('''
      SELECT m.*,
             (SELECT COUNT(*) FROM ${AppDatabase.tableChapter} c
               WHERE c.manga_key = m.manga_key AND c.status = 'downloaded')
             AS downloaded_chapters
      FROM ${AppDatabase.tableManga} m
      ORDER BY COALESCE(m.last_opened_at, m.added_at) DESC
    ''');

    return rows
        .map((r) => _mangaFromRow(
            r, (r['downloaded_chapters'] as num?)?.toInt() ?? 0))
        .toList(growable: false);
  }

  Future<int> _downloadedCount(String mangaKey) async {
    final result = await _raw.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.tableChapter} '
      "WHERE manga_key = ? AND status = 'downloaded'",
      [mangaKey],
    );
    return (result.first['c'] as num?)?.toInt() ?? 0;
  }

  // ── الفصول ────────────────────────────────────────────────────────────

  /// يدمج قائمة فصول قادمة من المصدر دون أن يمحو تقدّم التحميل أو القراءة.
  Future<void> mergeChapters(String mangaKey, List<Chapter> incoming) async {
    final existing = {
      for (final c in await chaptersOf(mangaKey)) c.remoteId: c,
    };

    final batch = _raw.batch();
    for (final c in incoming) {
      final old = existing[c.remoteId];
      batch.insert(
        AppDatabase.tableChapter,
        {
          'chapter_key': c.key,
          'manga_key': mangaKey,
          'remote_id': c.remoteId,
          'number': c.number,
          'title': c.title,
          'language': c.language,
          'sort_index': c.sortIndex,
          'page_count': old?.pageCount ?? c.pageCount,
          'downloaded_pages': old?.downloadedPages ?? 0,
          'status': (old?.status ?? ChapterStatus.notDownloaded).name,
          'last_page_read': old?.lastPageRead ?? 0,
          'published_at': c.publishedAt?.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    batch.update(
      AppDatabase.tableManga,
      {'total_chapters': incoming.length},
      where: 'manga_key = ?',
      whereArgs: [mangaKey],
    );

    await batch.commit(noResult: true);
  }

  Future<List<Chapter>> chaptersOf(String mangaKey) async {
    final rows = await _raw.query(
      AppDatabase.tableChapter,
      where: 'manga_key = ?',
      whereArgs: [mangaKey],
      orderBy: 'sort_index ASC',
    );
    return rows.map(_chapterFromRow).toList(growable: false);
  }

  Future<Chapter?> findChapter(String chapterKey) async {
    final rows = await _raw.query(
      AppDatabase.tableChapter,
      where: 'chapter_key = ?',
      whereArgs: [chapterKey],
      limit: 1,
    );
    return rows.isEmpty ? null : _chapterFromRow(rows.first);
  }

  /// كل ما كان في الطابور أو قيد التحميل عند إغلاق التطبيق، لاستئنافه.
  Future<List<Chapter>> pendingChapters() async {
    final rows = await _raw.query(
      AppDatabase.tableChapter,
      where: 'status IN (?, ?)',
      whereArgs: [ChapterStatus.queued.name, ChapterStatus.downloading.name],
      orderBy: 'manga_key ASC, sort_index ASC',
    );
    return rows.map(_chapterFromRow).toList(growable: false);
  }

  Future<void> updateChapterStatus(
    String chapterKey,
    ChapterStatus status, {
    int? downloadedPages,
    int? pageCount,
  }) {
    return _raw.update(
      AppDatabase.tableChapter,
      {
        'status': status.name,
        if (downloadedPages != null) 'downloaded_pages': downloadedPages,
        if (pageCount != null) 'page_count': pageCount,
      },
      where: 'chapter_key = ?',
      whereArgs: [chapterKey],
    );
  }

  Future<void> saveReadingPosition(String chapterKey, int page) => _raw.update(
        AppDatabase.tableChapter,
        {'last_page_read': page},
        where: 'chapter_key = ?',
        whereArgs: [chapterKey],
      );

  Future<void> resetChapter(String chapterKey) => _raw.update(
        AppDatabase.tableChapter,
        {
          'status': ChapterStatus.notDownloaded.name,
          'downloaded_pages': 0,
        },
        where: 'chapter_key = ?',
        whereArgs: [chapterKey],
      );

  // ── التحويل ───────────────────────────────────────────────────────────

  Manga _mangaFromRow(Map<String, Object?> r, int downloadedChapters) => Manga(
        sourceId: r['source_id'] as String,
        remoteId: r['remote_id'] as String,
        title: r['title'] as String,
        description: r['description'] as String? ?? '',
        author: r['author'] as String? ?? '',
        status: r['status'] as String? ?? '',
        remoteCoverUrl: r['remote_cover_url'] as String?,
        localCoverPath: r['local_cover_path'] as String?,
        totalChapters: (r['total_chapters'] as num?)?.toInt() ?? 0,
        downloadedChapters: downloadedChapters,
        addedAt: _date(r['added_at']),
        lastOpenedAt: _date(r['last_opened_at']),
      );

  Chapter _chapterFromRow(Map<String, Object?> r) => Chapter(
        mangaKey: r['manga_key'] as String,
        remoteId: r['remote_id'] as String,
        number: r['number'] as String,
        title: r['title'] as String? ?? '',
        language: r['language'] as String? ?? 'ar',
        sortIndex: (r['sort_index'] as num?)?.toInt() ?? 0,
        pageCount: (r['page_count'] as num?)?.toInt() ?? 0,
        downloadedPages: (r['downloaded_pages'] as num?)?.toInt() ?? 0,
        status: ChapterStatus.fromName(r['status'] as String?),
        lastPageRead: (r['last_page_read'] as num?)?.toInt() ?? 0,
        publishedAt: _date(r['published_at']),
      );

  static DateTime? _date(Object? millis) => millis == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch((millis as num).toInt());
}
