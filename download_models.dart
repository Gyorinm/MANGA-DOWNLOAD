import '../domain/entities/chapter.dart';

/// مهمة تحميل فصل واحد. الفصل هو أصغر وحدة قابلة للاستئناف.
class DownloadTask {
  DownloadTask({
    required this.mangaKey,
    required this.mangaTitle,
    required this.sourceId,
    required this.chapterKey,
    required this.chapterRemoteId,
    required this.chapterNumber,
  });

  final String mangaKey;
  final String mangaTitle;
  final String sourceId;
  final String chapterKey;
  final String chapterRemoteId;
  final String chapterNumber;

  factory DownloadTask.fromChapter({
    required Chapter chapter,
    required String mangaTitle,
    required String sourceId,
  }) {
    return DownloadTask(
      mangaKey: chapter.mangaKey,
      mangaTitle: mangaTitle,
      sourceId: sourceId,
      chapterKey: chapter.key,
      chapterRemoteId: chapter.remoteId,
      chapterNumber: chapter.number,
    );
  }
}

/// لقطة تقدّم تُبثّ إلى الواجهة عند كل تغيّر.
class DownloadProgress {
  const DownloadProgress({
    required this.chapterKey,
    required this.mangaKey,
    required this.mangaTitle,
    required this.chapterNumber,
    required this.status,
    required this.done,
    required this.total,
    this.message,
  });

  final String chapterKey;
  final String mangaKey;
  final String mangaTitle;
  final String chapterNumber;
  final ChapterStatus status;
  final int done;
  final int total;
  final String? message;

  double get ratio => total == 0 ? 0 : (done / total).clamp(0, 1);

  bool get isActive =>
      status == ChapterStatus.downloading || status == ChapterStatus.queued;
}
