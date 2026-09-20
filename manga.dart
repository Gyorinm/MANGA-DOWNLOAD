/// مانهوا كما يراها التطبيق، مستقلة عن أي مصدر أو قاعدة بيانات.
class Manga {
  const Manga({
    required this.sourceId,
    required this.remoteId,
    required this.title,
    this.description = '',
    this.author = '',
    this.status = '',
    this.remoteCoverUrl,
    this.localCoverPath,
    this.totalChapters = 0,
    this.downloadedChapters = 0,
    this.addedAt,
    this.lastOpenedAt,
  });

  /// معرّف المصدر، مثل `mangadex`.
  final String sourceId;

  /// معرّف المانهوا داخل ذلك المصدر.
  final String remoteId;

  final String title;
  final String description;
  final String author;
  final String status;

  final String? remoteCoverUrl;
  final String? localCoverPath;

  final int totalChapters;
  final int downloadedChapters;

  final DateTime? addedAt;
  final DateTime? lastOpenedAt;

  /// المفتاح الوحيد للمانهوا عبر كل المصادر، وهو مفتاح الجدول والمجلد.
  String get key => '$sourceId::$remoteId';

  bool get isInLibrary => addedAt != null;

  double get downloadRatio =>
      totalChapters == 0 ? 0 : downloadedChapters / totalChapters;

  Manga copyWith({
    String? title,
    String? description,
    String? author,
    String? status,
    String? remoteCoverUrl,
    String? localCoverPath,
    int? totalChapters,
    int? downloadedChapters,
    DateTime? addedAt,
    DateTime? lastOpenedAt,
  }) {
    return Manga(
      sourceId: sourceId,
      remoteId: remoteId,
      title: title ?? this.title,
      description: description ?? this.description,
      author: author ?? this.author,
      status: status ?? this.status,
      remoteCoverUrl: remoteCoverUrl ?? this.remoteCoverUrl,
      localCoverPath: localCoverPath ?? this.localCoverPath,
      totalChapters: totalChapters ?? this.totalChapters,
      downloadedChapters: downloadedChapters ?? this.downloadedChapters,
      addedAt: addedAt ?? this.addedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }
}
