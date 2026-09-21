import '../../../domain/entities/chapter.dart';
import '../../../domain/entities/manga.dart';
import '../manga_source.dart';

/// مصدر تجريبي ببيانات ثابتة وصفحات صور نائبة (placeholders).
///
/// غرضه إثبات أن التطبيق يتكيّف مع أكثر من مصدر: يظهر في البحث بجانب MangaDex،
/// ويمكن تفعيله وتعطيله من شاشة «مصادر التحميل». وهو نموذج مختصر لكيفية كتابة
/// أي مصدر جديد: كلاس واحد يطبّق خمس دوال.
class DemoSource implements MangaSource {
  static const _catalog = <_DemoEntry>[
    _DemoEntry('demo-1', 'Demo Manga One', 'مانهوا تجريبية للتأكد من عمل التحميل والقارئ.'),
    _DemoEntry('demo-2', 'Demo Manga Two', 'عمل تجريبي ثانٍ بعدد فصول أقل.'),
    _DemoEntry('demo-3', 'مانهوا تجريبية', 'عنوان عربي لاختبار البحث بالعربية.'),
  ];

  static const _chaptersPerManga = 5;
  static const _pagesPerChapter = 6;

  @override
  String get id => 'demo';

  @override
  String get displayName => 'مصدر تجريبي';

  @override
  List<String> get languages => const ['ar', 'en'];

  @override
  Map<String, String> get imageHeaders => const {};

  @override
  Future<List<Manga>> search(String query, {int page = 1}) async {
    if (page > 1) return const [];
    final q = query.trim().toLowerCase();
    return _catalog
        .where((e) => e.title.toLowerCase().contains(q))
        .map(_toManga)
        .toList(growable: false);
  }

  @override
  Future<Manga> details(String remoteId) async {
    final entry = _catalog.firstWhere(
      (e) => e.id == remoteId,
      orElse: () => throw StateError('عمل تجريبي غير معروف: $remoteId'),
    );
    return _toManga(entry);
  }

  @override
  Future<List<Chapter>> chapters(String remoteId,
      {String language = 'ar'}) async {
    final mangaKey = '$id::$remoteId';
    return List.generate(
      _chaptersPerManga,
      (i) => Chapter(
        mangaKey: mangaKey,
        remoteId: '$remoteId-ch${i + 1}',
        number: '${i + 1}',
        title: '',
        language: language,
        sortIndex: i,
        pageCount: _pagesPerChapter,
      ),
      growable: false,
    );
  }

  @override
  Future<List<String>> pageUrls(String chapterRemoteId) async {
    // صور نائبة من خدمة placehold.co؛ تحتاج اتصالًا وقت التحميل فقط.
    return List.generate(
      _pagesPerChapter,
      (i) => 'https://placehold.co/800x1200.png'
          '?text=$chapterRemoteId+p${i + 1}',
      growable: false,
    );
  }

  Manga _toManga(_DemoEntry e) => Manga(
        sourceId: id,
        remoteId: e.id,
        title: e.title,
        description: e.description,
        author: 'مصدر تجريبي',
        status: 'مكتملة',
        remoteCoverUrl: 'https://placehold.co/400x600.png?text=${e.id}',
      );
}

class _DemoEntry {
  const _DemoEntry(this.id, this.title, this.description);

  final String id;
  final String title;
  final String description;
}
