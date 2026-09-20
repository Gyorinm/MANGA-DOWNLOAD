import 'package:dio/dio.dart';

import '../../../core/http/http_client.dart';
import '../../../core/utils/result.dart';
import '../../../domain/entities/chapter.dart';
import '../../../domain/entities/manga.dart';
import '../manga_source.dart';

/// مصدر MangaDex عبر واجهته البرمجية الرسمية والمجانية.
///
/// اختير مصدرًا أوّل لأنه يوفّر API معلنة ومستقرة، فلا يحتاج التطبيق إلى
/// كشط HTML هشّ يتعطّل مع كل تعديل في تصميم الموقع.
class MangaDexSource implements MangaSource {
  MangaDexSource(this._http);

  final HttpClient _http;

  static const _api = 'https://api.mangadex.org';
  static const _covers = 'https://uploads.mangadex.org/covers';

  @override
  String get id => 'mangadex';

  @override
  String get displayName => 'MangaDex';

  @override
  List<String> get languages => const ['ar', 'en'];

  @override
  Future<List<Manga>> search(String query, {int page = 1}) async {
    const limit = 20;
    final json = await _get('$_api/manga', {
      'title': query,
      'limit': limit,
      'offset': (page - 1) * limit,
      'includes[]': ['cover_art', 'author'],
      'order[relevance]': 'desc',
      'contentRating[]': ['safe', 'suggestive'],
    });

    final data = (json['data'] as List?) ?? const [];
    return data
        .cast<Map<String, dynamic>>()
        .map(_mapManga)
        .toList(growable: false);
  }

  @override
  Future<Manga> details(String remoteId) async {
    final json = await _get('$_api/manga/$remoteId', {
      'includes[]': ['cover_art', 'author'],
    });
    final data = json['data'];
    if (data is! Map<String, dynamic>) throw AppFailure.parsing();
    return _mapManga(data);
  }

  @override
  Future<List<Chapter>> chapters(String remoteId,
      {String language = 'ar'}) async {
    final collected = <Map<String, dynamic>>[];
    var offset = 0;
    const limit = 500;

    // الواجهة مُصفّحة؛ نستمر حتى نستهلك كل الفصول.
    while (true) {
      final json = await _get('$_api/manga/$remoteId/feed', {
        'translatedLanguage[]': [language],
        'order[chapter]': 'asc',
        'limit': limit,
        'offset': offset,
        'contentRating[]': ['safe', 'suggestive'],
        'includeExternalUrl': 0,
      });

      final data = ((json['data'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      collected.addAll(data);

      final total = (json['total'] as num?)?.toInt() ?? collected.length;
      offset += limit;
      if (data.isEmpty || offset >= total) break;
    }

    final mangaKey = '$id::$remoteId';
    final unique = <String, Chapter>{};

    for (var i = 0; i < collected.length; i++) {
      final item = collected[i];
      final attrs = (item['attributes'] as Map?)?.cast<String, dynamic>() ?? {};
      final number = (attrs['chapter'] as String?)?.trim();
      if (number == null || number.isEmpty) continue;

      // ترجمات متعددة لنفس الرقم: نحتفظ بالأولى فقط لتفادي التكرار.
      if (unique.containsKey(number)) continue;

      unique[number] = Chapter(
        mangaKey: mangaKey,
        remoteId: item['id'] as String,
        number: number,
        title: (attrs['title'] as String?) ?? '',
        language: language,
        sortIndex: i,
        pageCount: (attrs['pages'] as num?)?.toInt() ?? 0,
        publishedAt: DateTime.tryParse(attrs['publishAt'] as String? ?? ''),
      );
    }

    final list = unique.values.toList()
      ..sort((a, b) => _numeric(a.number).compareTo(_numeric(b.number)));

    return List.generate(
      list.length,
      (i) => Chapter(
        mangaKey: list[i].mangaKey,
        remoteId: list[i].remoteId,
        number: list[i].number,
        title: list[i].title,
        language: list[i].language,
        sortIndex: i,
        pageCount: list[i].pageCount,
        publishedAt: list[i].publishedAt,
      ),
      growable: false,
    );
  }

  @override
  Future<List<String>> pageUrls(String chapterRemoteId) async {
    final json = await _get('$_api/at-home/server/$chapterRemoteId', const {});
    final baseUrl = json['baseUrl'] as String?;
    final chapter = (json['chapter'] as Map?)?.cast<String, dynamic>();
    if (baseUrl == null || chapter == null) throw AppFailure.parsing();

    final hash = chapter['hash'] as String?;
    final files = (chapter['data'] as List?)?.cast<String>() ?? const [];
    if (hash == null || files.isEmpty) throw AppFailure.parsing();

    return files
        .map((f) => '$baseUrl/data/$hash/$f')
        .toList(growable: false);
  }

  // ── داخلي ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(
      String url, Map<String, dynamic> query) async {
    try {
      final res = await _http.get<Map<String, dynamic>>(url, query: query);
      final body = res.data;
      if (body == null) throw AppFailure.parsing();
      return body;
    } on DioException catch (e) {
      throw AppFailure.network(e);
    } on FormatException catch (e) {
      throw AppFailure.parsing(e);
    }
  }

  Manga _mapManga(Map<String, dynamic> item) {
    final attrs = (item['attributes'] as Map?)?.cast<String, dynamic>() ?? {};
    final relationships =
        ((item['relationships'] as List?) ?? const []).cast<Map<String, dynamic>>();

    return Manga(
      sourceId: id,
      remoteId: item['id'] as String,
      title: _localized(attrs['title']) ?? 'بلا عنوان',
      description: _localized(attrs['description']) ?? '',
      author: _relationAttr(relationships, 'author', 'name') ?? '',
      status: _statusLabel(attrs['status'] as String?),
      remoteCoverUrl: _coverUrl(item['id'] as String, relationships),
    );
  }

  /// يفضّل العربية ثم الإنجليزية ثم أول قيمة متاحة.
  String? _localized(Object? field) {
    if (field is String) return field;
    if (field is! Map) return null;
    final map = field.cast<String, dynamic>();
    for (final lang in const ['ar', 'en']) {
      final value = map[lang];
      if (value is String && value.isNotEmpty) return value;
    }
    final first = map.values.whereType<String>().where((v) => v.isNotEmpty);
    return first.isEmpty ? null : first.first;
  }

  String? _relationAttr(
      List<Map<String, dynamic>> relations, String type, String attr) {
    for (final r in relations) {
      if (r['type'] == type) {
        final a = (r['attributes'] as Map?)?.cast<String, dynamic>();
        final value = a?[attr];
        if (value is String && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  String? _coverUrl(String mangaId, List<Map<String, dynamic>> relations) {
    final file = _relationAttr(relations, 'cover_art', 'fileName');
    if (file == null) return null;
    // نسخة 512 بكسل: كافية للغلاف وأخفّ على الشبكة والقرص.
    return '$_covers/$mangaId/$file.512.jpg';
  }

  String _statusLabel(String? raw) => switch (raw) {
        'ongoing' => 'مستمرة',
        'completed' => 'مكتملة',
        'hiatus' => 'متوقّفة مؤقتًا',
        'cancelled' => 'ملغاة',
        _ => '',
      };

  static double _numeric(String chapterNumber) =>
      double.tryParse(chapterNumber) ?? double.maxFinite;
}
