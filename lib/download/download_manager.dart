import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../core/http/http_client.dart';
import '../core/storage/file_storage.dart';
import '../data/local/library_dao.dart';
import '../data/repositories/library_repository.dart';
import '../data/sources/source_registry.dart';
import '../domain/entities/chapter.dart';
import '../domain/entities/manga.dart';
import 'download_models.dart';

/// طابور تحميل واحد لكل التطبيق.
///
/// قواعد التصميم:
/// • الفصل وحدة الاستئناف: لا يُعاد تنزيل صفحة موجودة على القرص.
/// • التزامن محدود ([maxConcurrent]) حتى لا يُخنق اتصال المستخدم.
/// • كل تغيّر يُكتب في قاعدة البيانات فورًا، فيصمد أمام إغلاق التطبيق.
class DownloadManager {
  DownloadManager({
    required HttpClient http,
    required FileStorage storage,
    required LibraryDao dao,
    required SourceRegistry registry,
    required LibraryRepository repository,
    this.maxConcurrent = 3,
  })  : _http = http,
        _storage = storage,
        _dao = dao,
        _registry = registry,
        _repository = repository;

  final HttpClient _http;
  final FileStorage _storage;
  final LibraryDao _dao;
  final SourceRegistry _registry;
  final LibraryRepository _repository;
  final int maxConcurrent;

  final Queue<DownloadTask> _queue = Queue();
  final Map<String, CancelToken> _active = {};
  final Map<String, DownloadProgress> _snapshots = {};
  final _events = StreamController<DownloadProgress>.broadcast();

  Stream<DownloadProgress> get events => _events.stream;

  List<DownloadProgress> get snapshot =>
      _snapshots.values.toList(growable: false);

  bool get isBusy => _active.isNotEmpty || _queue.isNotEmpty;

  // ── الواجهة العامة ────────────────────────────────────────────────────

  /// «تحميل المانهوا»: يضيفها إلى المكتبة، يحفظ الغلاف، ثم يُدرج الفصول.
  Future<void> enqueueManga({
    required Manga manga,
    required List<Chapter> chapters,
  }) async {
    final saved = await _repository.addToLibrary(manga, chapters);
    await _saveCover(saved);

    final stored = await _dao.chaptersOf(saved.key);
    for (final chapter in stored) {
      if (chapter.status == ChapterStatus.downloaded) continue;
      await _enqueueChapter(saved, chapter);
    }
    _pump();
  }

  /// تحميل فصول مختارة فقط.
  Future<void> enqueueChapters({
    required Manga manga,
    required List<Chapter> chapters,
  }) async {
    for (final chapter in chapters) {
      if (chapter.status == ChapterStatus.downloaded) continue;
      await _enqueueChapter(manga, chapter);
    }
    _pump();
  }

  /// يستأنف ما كان معلّقًا عند آخر إغلاق للتطبيق.
  Future<void> resumePending() async {
    final pending = await _dao.pendingChapters();
    for (final chapter in pending) {
      final manga = await _dao.findManga(chapter.mangaKey);
      if (manga == null) continue;
      await _enqueueChapter(manga, chapter);
    }
    _pump();
  }

  void cancel(String chapterKey) {
    _queue.removeWhere((t) => t.chapterKey == chapterKey);
    _active[chapterKey]?.cancel('ألغى المستخدم التحميل');
  }

  void cancelManga(String mangaKey) {
    _queue.removeWhere((t) => t.mangaKey == mangaKey);
    for (final entry in _active.entries.toList()) {
      if (_snapshots[entry.key]?.mangaKey == mangaKey) {
        entry.value.cancel('ألغى المستخدم التحميل');
      }
    }
  }

  void clearFinished() {
    _snapshots.removeWhere((_, v) => !v.isActive);
  }

  // ── داخلي ─────────────────────────────────────────────────────────────

  Future<void> _enqueueChapter(Manga manga, Chapter chapter) async {
    final alreadyQueued = _queue.any((t) => t.chapterKey == chapter.key) ||
        _active.containsKey(chapter.key);
    if (alreadyQueued) return;

    await _dao.updateChapterStatus(chapter.key, ChapterStatus.queued);
    _queue.add(DownloadTask.fromChapter(
      chapter: chapter,
      mangaTitle: manga.title,
      sourceId: manga.sourceId,
    ));
    _emit(chapter.key, DownloadProgress(
      chapterKey: chapter.key,
      mangaKey: manga.key,
      mangaTitle: manga.title,
      chapterNumber: chapter.number,
      status: ChapterStatus.queued,
      done: 0,
      total: chapter.pageCount,
    ));
  }

  void _pump() {
    while (_active.length < maxConcurrent && _queue.isNotEmpty) {
      final task = _queue.removeFirst();
      final token = CancelToken();
      _active[task.chapterKey] = token;
      unawaited(_runTask(task, token).whenComplete(() {
        _active.remove(task.chapterKey);
        _repository.notifyChanged();
        _pump();
      }));
    }
  }

  Future<void> _runTask(DownloadTask task, CancelToken token) async {
    void report(ChapterStatus status, int done, int total, [String? message]) {
      _emit(
        task.chapterKey,
        DownloadProgress(
          chapterKey: task.chapterKey,
          mangaKey: task.mangaKey,
          mangaTitle: task.mangaTitle,
          chapterNumber: task.chapterNumber,
          status: status,
          done: done,
          total: total,
          message: message,
        ),
      );
    }

    try {
      final source = _registry.require(task.sourceId);
      await _dao.updateChapterStatus(task.chapterKey, ChapterStatus.downloading);
      report(ChapterStatus.downloading, 0, 0);

      final urls = await source.pageUrls(task.chapterRemoteId);
      await _dao.updateChapterStatus(
        task.chapterKey,
        ChapterStatus.downloading,
        pageCount: urls.length,
      );

      final dir = await _storage
          .ensure(_storage.chapterDir(task.mangaKey, task.chapterRemoteId));

      var done = 0;
      for (var i = 0; i < urls.length; i++) {
        if (token.isCancelled) break;

        final url = urls[i];
        final ext = _extensionOf(url);
        final target =
            _storage.pagePath(task.mangaKey, task.chapterRemoteId, i, ext);

        // استئناف: صفحة موجودة وغير فارغة تُتخطّى.
        final file = File(target);
        if (await file.exists() && await file.length() > 0) {
          done++;
          report(ChapterStatus.downloading, done, urls.length);
          continue;
        }

        // التنزيل إلى ملف مؤقت ثم إعادة التسمية، فلا تبقى ملفات نصف مكتملة.
        final tmp = '$target.part';
        await _http.download(
          url,
          tmp,
          cancelToken: token,
          headers: source.imageHeaders,
        );
        await File(tmp).rename(target);

        done++;
        await _dao.updateChapterStatus(
          task.chapterKey,
          ChapterStatus.downloading,
          downloadedPages: done,
        );
        report(ChapterStatus.downloading, done, urls.length);
      }

      if (token.isCancelled) {
        await _dao.updateChapterStatus(task.chapterKey, ChapterStatus.failed,
            downloadedPages: done);
        report(ChapterStatus.failed, done, urls.length, 'أُلغي التحميل');
        return;
      }

      await _dao.updateChapterStatus(
        task.chapterKey,
        ChapterStatus.downloaded,
        downloadedPages: done,
        pageCount: urls.length,
      );
      report(ChapterStatus.downloaded, done, urls.length);
      unawaited(_cleanPartials(dir));
    } catch (e) {
      final current = await _dao.findChapter(task.chapterKey);
      await _dao.updateChapterStatus(task.chapterKey, ChapterStatus.failed);
      report(
        ChapterStatus.failed,
        current?.downloadedPages ?? 0,
        current?.pageCount ?? 0,
        'توقّف الفصل ${task.chapterNumber}. اضغط لإعادة المحاولة.',
      );
    }
  }

  Future<void> _saveCover(Manga manga) async {
    final url = manga.remoteCoverUrl;
    if (url == null || url.isEmpty) return;
    try {
      await _storage.ensure(_storage.mangaDir(manga.key));
      final path = _storage.coverPath(manga.key);
      if (await File(path).exists()) return;
      await _http.download(
        url,
        path,
        headers: _registry.byId(manga.sourceId)?.imageHeaders,
      );
      await _dao.setLocalCover(manga.key, path);
      _repository.notifyChanged();
    } catch (_) {
      // الغلاف ليس حرجًا: تفشل صورته ولا يفشل التحميل كله.
    }
  }

  Future<void> _cleanPartials(Directory dir) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.part')) {
        await entity.delete();
      }
    }
  }

  void _emit(String key, DownloadProgress progress) {
    _snapshots[key] = progress;
    if (!_events.isClosed) _events.add(progress);
  }

  static String _extensionOf(String url) {
    final ext = p.extension(Uri.parse(url).path).toLowerCase();
    const allowed = {'.jpg', '.jpeg', '.png', '.webp'};
    return allowed.contains(ext) ? ext : '.jpg';
  }

  void dispose() {
    for (final token in _active.values) {
      token.cancel('إغلاق التطبيق');
    }
    _events.close();
  }
}
