/// حالة الفصل داخل المكتبة المحلية.
enum ChapterStatus {
  /// لم يُطلب تحميله بعد.
  notDownloaded,

  /// في الطابور بانتظار دوره.
  queued,

  /// جارٍ تنزيل صفحاته الآن.
  downloading,

  /// كل الصفحات موجودة على الجهاز.
  downloaded,

  /// توقّف بخطأ، ويمكن استئنافه من آخر صفحة نجحت.
  failed;

  static ChapterStatus fromName(String? name) => ChapterStatus.values.firstWhere(
        (s) => s.name == name,
        orElse: () => ChapterStatus.notDownloaded,
      );

  String get label => switch (this) {
        ChapterStatus.notDownloaded => 'غير محمّل',
        ChapterStatus.queued => 'في الانتظار',
        ChapterStatus.downloading => 'جارٍ التحميل',
        ChapterStatus.downloaded => 'محمّل',
        ChapterStatus.failed => 'متوقّف',
      };
}

class Chapter {
  const Chapter({
    required this.mangaKey,
    required this.remoteId,
    required this.number,
    this.title = '',
    this.language = 'ar',
    this.sortIndex = 0,
    this.pageCount = 0,
    this.downloadedPages = 0,
    this.status = ChapterStatus.notDownloaded,
    this.lastPageRead = 0,
    this.publishedAt,
  });

  final String mangaKey;
  final String remoteId;

  /// رقم الفصل كنص، لأن بعض المصادر تستعمل أرقامًا كسرية مثل 12.5.
  final String number;
  final String title;
  final String language;

  /// ترتيب ثابت للعرض، يُحسب مرة عند الجلب.
  final int sortIndex;

  final int pageCount;
  final int downloadedPages;
  final ChapterStatus status;
  final int lastPageRead;
  final DateTime? publishedAt;

  String get key => '$mangaKey::$remoteId';

  String get displayName =>
      title.isEmpty ? 'الفصل $number' : 'الفصل $number — $title';

  bool get isReadable => status == ChapterStatus.downloaded;

  double get progress =>
      pageCount == 0 ? 0 : (downloadedPages / pageCount).clamp(0, 1);

  Chapter copyWith({
    String? title,
    int? pageCount,
    int? downloadedPages,
    ChapterStatus? status,
    int? lastPageRead,
  }) {
    return Chapter(
      mangaKey: mangaKey,
      remoteId: remoteId,
      number: number,
      title: title ?? this.title,
      language: language,
      sortIndex: sortIndex,
      pageCount: pageCount ?? this.pageCount,
      downloadedPages: downloadedPages ?? this.downloadedPages,
      status: status ?? this.status,
      lastPageRead: lastPageRead ?? this.lastPageRead,
      publishedAt: publishedAt,
    );
  }
}
