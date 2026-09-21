import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/http/http_client.dart';
import '../../../core/utils/result.dart';
import '../../../domain/entities/chapter.dart';
import '../../../domain/entities/manga.dart';
import '../manga_source.dart';
import 'custom_source_config.dart';

/// مصدر يتصل بخادم مكتبة شخصية يعمل بواجهة Komga، يديره المستخدم بنفسه
/// (على حاسوبه أو جهاز التخزين في بيته). العنوان وبيانات الدخول من إدخاله.
class KomgaSource implements MangaSource {
  KomgaSource(this._http, this.config);

  final HttpClient _http;
  final CustomSourceConfig config;

  String get _base => config.baseUrl.replaceAll(RegExp(r'/+$'), '');

  @override
  String get id => config.id;

  @override
  String get displayName => config.name;

  /// خادم شخصي: اللغة بحسب ما رفعه صاحبه، فلا قائمة ثابتة.
  @override
  List<String> get languages => const [];

  Map<String, String> get _auth {
    if (config.username.isEmpty) return const {};
    final token = base64Encode(utf8.encode('${config.username}:${config.password}'));
    return {'Authorization': 'Basic $token'};
  }

  /// الأغلفة والصفحات على الخادم محميّة، فتحتاج ترويسة الدخول نفسها.
  @override
  Map<String, String> get imageHeaders => _auth;

  /// يُستدعى عند إضافة المصدر: يتأكد أن العنوان صحيح وبيانات الدخول مقبولة.
  Future<void> verifyConnection() async {
    await _get('/api/v1/series', {'page': 0, 'size': 1});
  }

  @override
  Future<List<Manga>> search(String query, {int page = 1}) async {
    final json = _map(await _get('/api/v1/series', {
      'search': query,
      'page': page - 1,
      'size': 20,
    }));
    final content = (json['content'] as List?) ?? const [];
    return content.map((e) => _mapSeries(_map(e))).toList(growable: false);
  }

  @override
  Future<Manga> details(String remoteId) async {
    final json = _map(await _get('/api/v1/series/$remoteId'));
    return _mapSeries(json);
  }

  @override
  Future<List<Chapter>> chapters(String remoteId,
      {String language = 'ar'}) async {
    final json = _map(await _get('/api/v1/series/$remoteId/books', {
      'unpaged': true,
      'sort': 'metadata.numberSort,asc',
    }));
    final books = (json['content'] as List?) ?? const [];
    final mangaKey = '$id::$remoteId';

    return List.generate(books.length, (i) {
      final book = _map(books[i]);
      final meta = _map(book['metadata']);
      final media = _map(book['media']);

      var number = (meta['number'] as String?)?.trim() ?? '';
      if (number.isEmpty) number = '${book['number'] ?? i + 1}';

      // عنوان الكتاب الافتراضي في Komga هو اسم الملف؛ لا فائدة من عرضه.
      var title = (meta['title'] as String?)?.trim() ?? '';
      if (title == book['name']) title = '';

      return Chapter(
        mangaKey: mangaKey,
        remoteId: book['id'] as String,
        number: number,
        title: title,
        language: language,
        sortIndex: i,
        pageCount: (media['pagesCount'] as num?)?.toInt() ?? 0,
      );
    }, growable: false);
  }

  @override
  Future<List<String>> pageUrls(String chapterRemoteId) async {
    final data = await _get('/api/v1/books/$chapterRemoteId/pages');
    if (data is! List || data.isEmpty) throw AppFailure.parsing();

    return data
        .map((p) => '$_base/api/v1/books/$chapterRemoteId/pages/${_map(p)['number']}')
        .toList(growable: false);
  }

  // ── داخلي ─────────────────────────────────────────────────────────────

  Future<dynamic> _get(String path, [Map<String, dynamic>? query]) async {
    try {
      final res = await _http.get<dynamic>(
        '$_base$path',
        query: query,
        options: Options(headers: _auth),
      );
      final body = res.data;
      if (body == null) throw AppFailure.parsing();
      return body;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        throw const AppFailure('اسم المستخدم أو كلمة المرور غير صحيحة.');
      }
      if (code == 404) {
        throw const AppFailure(
          'لم أجد خادم Komga في هذا العنوان. تحقّق من الرابط والمنفذ.',
        );
      }
      throw AppFailure.network(e);
    }
  }

  Manga _mapSeries(Map<String, dynamic> series) {
    final meta = _map(series['metadata']);
    final booksMeta = _map(series['booksMetadata']);
    final seriesId = series['id'] as String;

    final metaTitle = (meta['title'] as String?)?.trim() ?? '';
    final authors = ((booksMeta['authors'] as List?) ?? const [])
        .map((a) => (_map(a)['name'] as String?) ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .join('، ');

    return Manga(
      sourceId: id,
      remoteId: seriesId,
      title: metaTitle.isNotEmpty
          ? metaTitle
          : ((series['name'] as String?) ?? 'بلا عنوان'),
      description: (meta['summary'] as String?) ?? '',
      author: authors,
      status: _statusLabel(meta['status'] as String?),
      remoteCoverUrl: '$_base/api/v1/series/$seriesId/thumbnail',
    );
  }

  String _statusLabel(String? raw) => switch (raw) {
        'ONGOING' => 'مستمرة',
        'ENDED' => 'مكتملة',
        'HIATUS' => 'متوقّفة مؤقتًا',
        'ABANDONED' => 'ملغاة',
        _ => '',
      };

  Map<String, dynamic> _map(Object? value) =>
      value is Map ? value.cast<String, dynamic>() : const <String, dynamic>{};
}
