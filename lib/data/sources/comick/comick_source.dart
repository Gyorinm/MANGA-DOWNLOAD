import 'package:dio/dio.dart';

import '../../../core/http/http_client.dart';
import '../../../core/utils/result.dart';
import '../../../domain/entities/chapter.dart';
import '../../../domain/entities/manga.dart';
import '../manga_source.dart';

/// مصدر ComicK عبر واجهة JSON العامة.
///
/// المعرّف الذي نحتفظ به هو HID الخاص بـ ComicK، لذلك يبقى mangaKey ثابتًا
/// حتى لو تغيّر رابط الصفحة البشري.
class ComicKSource implements MangaSource {
  ComicKSource(this._http);

  final HttpClient _http;

  static const _api = 'https://api.comick.io';
  static const _images = 'https://meo.comick.pictures';

  @override
  String get id => 'comick';

  @override
  String get displayName => 'ComicK';

  @override
  List<String> get languages => const ['ar', 'en'];

  /// ComicK قد يحتاج Referer عند جلب صور الصفحات.
  @override
  Map<String, String> get imageHeaders => const {
        'Referer': 'https://comick.io/',
      };

  @override
  Future<List<Manga>> search(String query, {int page = 1}) async {
    final raw = await _get('/v1.0/search', {
      'q': query,
      'limit': 20,
      'page': page,
    });

    final items = raw is List ? raw : const [];
    return items
        .whereType<Map>()
        .map((item) => _mapSearch(item.cast<String, dynamic>()))
        .where((manga) => manga != null)
        .cast<Manga>()
        .toList(growable: false);
  }

  @override
  Future<Manga> details(String remoteId) async {
    final raw = await _get('/comic/$remoteId');
    final data = _unwrapMap(raw, 'comic');

    final title = (data['title'] as String?)?.trim();
    if (title == null || title.isEmpty) throw AppFailure.parsing();

    return Manga(
      sourceId: id,
      remoteId: remoteId,
      title: title,
      description: (data['desc'] as String?) ?? '',
      status: (data['status_text'] as String?) ?? '',
      remoteCoverUrl: _coverUrl(data['md_covers']),
    );
  }

  @override
  Future<List<Chapter>> chapters(
    String remoteId, {
    String language = 'ar',
  }) async {
    final preferred = await _fetchChapters(remoteId, language);
    final raw = preferred.isNotEmpty || language == 'en'
        ? preferred
        : await _fetchChapters(remoteId, 'en');

    final unique = <String, Map<String, dynamic>>{};
    for (final item in raw) {
      final number = (item['chap'] as String?)?.trim();
      final hid = item['hid'] as String?;
      if (number == null || number.isEmpty || hid == null || hid.isEmpty) {
        continue;
      }

      final previous = unique[number];
      if (previous == null ||
          ((item['up_count'] as num?)?.toInt() ?? 0) >
              ((previous['up_count'] as num?)?.toInt() ?? 0)) {
        unique[number] = item;
      }
    }

    final items = unique.values.toList()
      ..sort((a, b) => _chapterNumber(a['chap']).compareTo(
            _chapterNumber(b['chap']),
          ));

    return List.generate(items.length, (index) {
      final item = items[index];
      final itemLanguage = (item['lang'] as String?)?.trim() ?? language;
      return Chapter(
        mangaKey: '$id::$remoteId',
        remoteId: item['hid'] as String,
        number: (item['chap'] as String?)?.trim() ?? '',
        title: (item['title'] as String?)?.trim() ?? '',
        language: itemLanguage.isEmpty ? language : itemLanguage,
        sortIndex: index,
        pageCount: 0,
        publishedAt: DateTime.tryParse(
          item['updated_at'] as String? ?? '',
        ),
      );
    }, growable: false);
  }

  Future<List<Map<String, dynamic>>> _fetchChapters(
    String remoteId,
    String language,
  ) async {
    final raw = await _get('/comic/$remoteId/chapters', {
      'lang': language,
      'page': 1,
      'limit': 100,
      'chap-order': 1,
    });

    final map = _unwrapMap(raw, '');
    final chapters = (map['chapters'] as List?) ?? const [];
    return chapters
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList(growable: false);
  }

  @override
  Future<List<String>> pageUrls(String chapterRemoteId) async {
    final raw = await _get('/chapter/$chapterRemoteId');
    final data = _unwrapMap(raw, 'chapter');
    final images = (data['md_images'] as List?) ?? const [];

    final urls = <String>[];
    for (final item in images.whereType<Map>()) {
      final image = item.cast<String, dynamic>();
      final key = image['b2key'] as String?;
      if (key == null || key.isEmpty) continue;

      final width = (image['w'] as num?)?.toInt();
      urls.add(
        width == null || width <= 0
            ? '$_images/$key'
            : '$_images/$key?width=$width',
      );
    }

    if (urls.isEmpty) throw AppFailure.parsing();
    return urls;
  }

  Future<dynamic> _get(
    String path,
    Map<String, dynamic> query,
  ) async {
    try {
      final response = await _http.get<dynamic>(
        '$_api$path',
        query: query,
        options: Options(
          headers: const {
            'Referer': 'https://comick.io/',
          },
        ),
      );
      final body = response.data;
      if (body == null) throw AppFailure.parsing();
      return body;
    } on DioException catch (e) {
      throw AppFailure.network(e);
    } on FormatException catch (e) {
      throw AppFailure.parsing(e);
    }
  }

  Manga? _mapSearch(Map<String, dynamic> item) {
    final hid = item['hid'] as String?;
    final title =
        (item['title'] as String?)?.trim() ??
        (item['slug'] as String?)?.trim();

    if (hid == null || hid.isEmpty || title == null || title.isEmpty) {
      return null;
    }

    final rating = (item['content_rating'] as String?)?.toLowerCase() ?? '';
    if (rating == 'pornographic' || rating == 'erotica') return null;

    return Manga(
      sourceId: id,
      remoteId: hid,
      title: title,
      remoteCoverUrl: _coverUrl(item['md_covers']),
      status: (item['status_text'] as String?) ?? '',
    );
  }

  String? _coverUrl(Object? raw) {
    final covers = raw is List ? raw : const [];
    for (final item in covers.whereType<Map>()) {
      final key = item['b2key'] as String?;
      if (key != null && key.isNotEmpty) return '$_images/$key';
    }
    return null;
  }

  Map<String, dynamic> _unwrapMap(Object? raw, String key) {
    if (raw is Map) {
      final map = raw.cast<String, dynamic>();
      if (key.isNotEmpty && map[key] is Map) {
        return (map[key] as Map).cast<String, dynamic>();
      }
      return map;
    }
    throw AppFailure.parsing();
  }

  double _chapterNumber(Object? raw) {
    final value = double.tryParse((raw as String?)?.trim() ?? '');
    return value ?? double.infinity;
  }
}
