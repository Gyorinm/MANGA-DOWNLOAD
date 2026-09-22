import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:maktaba/core/http/http_client.dart';
import 'package:maktaba/core/utils/result.dart';
import 'package:maktaba/domain/entities/chapter.dart';
import 'package:maktaba/domain/entities/manga.dart';
import 'package:maktaba/data/sources/manga_source.dart';
import 'package:maktaba/data/sources/html_source_utils.dart';

/// مصدر Team-X / Olympus Staff.
class OlympusStaffSource implements MangaSource {
  OlympusStaffSource(this._http);

  final HttpClient _http;
  static const _base = 'https://olympustaff.com';

  @override
  String get id => 'olympus';

  @override
  String get displayName => 'Olympus Staff (Team-X)';

  @override
  List<String> get languages => const ['ar'];

  @override
  Map<String, String> get imageHeaders => const {'Referer': 'https://olympustaff.com/'};

  @override
  Future<List<Manga>> search(String query, {int page = 1}) async {
    final direct = await _directSlugSearch(query);
    if (direct != null) return [direct];
    final url = '$_base/?search=${Uri.encodeQueryComponent(query.trim())}&page=${page < 1 ? 1 : page}';
    try {
      return _parseMangaGrid(await _document(url));
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<Manga> details(String remoteId) async {
    for (final url in ['$_base/series/$remoteId', '$_base/manga/$remoteId/', '$_base/manga/$remoteId']) {
      try {
        final document = await _document(url);
        final title = cleanText(document.querySelector('h1, .author-info-title h6, .title')?.text ?? remoteId);
        if (title.isEmpty) continue;
        final cover = imageUrl(_base, document.querySelector('img[alt="Manga Image"], img.shadow-sm, .text-right img, .summary_image img, .profile-manga img'));
        final paragraphs = document.querySelectorAll('p').map((p) => cleanText(p.text)).where((text) => text.length > 30 && !text.contains('http')).toList();
        final author = _fullInfoValue(document, 'الرسام');
        return Manga(
          sourceId: id,
          remoteId: remoteId,
          title: title,
          description: paragraphs.isEmpty ? '' : paragraphs.first,
          author: author,
          status: detectStatus(cleanText(document.body?.text ?? '')),
          remoteCoverUrl: cover.isEmpty ? null : cover,
        );
      } catch (_) {}
    }
    throw const AppFailure('لم أجد هذه المانجا في Olympus Staff.');
  }

  @override
  Future<List<Chapter>> chapters(String remoteId, {String language = 'ar'}) async {
    final found = <String, Chapter>{};
    final pages = <String>[
      '$_base/series/$remoteId',
      '$_base/manga/$remoteId/',
      '$_base/manga/$remoteId',
    ];

    for (final pageUrl in pages) {
      try {
        final document = await _document(pageUrl);
        _collectChapters(document, pageUrl, remoteId, language, found, 0);
        final maxPage = _maxPage(document).clamp(1, 100);
        for (var page = 2; page <= maxPage; page++) {
          final before = found.length;
          final pageDocument = await _document('$pageUrl?page=$page');
          _collectChapters(pageDocument, pageUrl, remoteId, language, found, page);
          if (found.length == before) break;
        }
      } catch (_) {
        // جرّب شكل الصفحة التالي؛ لا تسقط العملية بسبب شكل رابط غير موجود.
      }
    }

    final sorted = found.values.toList()
      ..sort((a, b) => chapterSortNumber(a.number).compareTo(chapterSortNumber(b.number)));
    return [
      for (var i = 0; i < sorted.length; i++)
        Chapter(
          mangaKey: sorted[i].mangaKey,
          remoteId: sorted[i].remoteId,
          number: sorted[i].number,
          title: sorted[i].title,
          language: language,
          sortIndex: i,
          pageCount: sorted[i].pageCount,
        ),
    ];
  }

  void _collectChapters(dynamic document, String baseUrl, String remoteId, String language, Map<String, Chapter> found, int pageIndex) {
    for (final link in document.querySelectorAll('a[href]')) {
      final href = absoluteUrl(baseUrl, link.attributes['href'] ?? '');
      if (!_isChapterUrl(href, remoteId)) continue;
      final number = _chapterNumber(href, link.text);
      if (number == null) continue;
      final text = cleanText(link.text);
      final paid = link.parent?.classes.any((c) => c.toLowerCase().contains('lock')) == true;
      found[href] = Chapter(
        mangaKey: '$id::$remoteId',
        remoteId: href,
        number: number,
        title: paid && text.isEmpty ? 'الفصل $number (مدفوع)' : _chapterTitle(text, number),
        language: language,
        sortIndex: pageIndex,
        pageCount: 0,
      );
    }
  }

  @override
  Future<List<String>> pageUrls(String chapterRemoteId) async {
    final document = await _document(chapterRemoteId, headers: {'Referer': '$_base/'});
    final urls = <String>[];
    for (final image in document.querySelectorAll('img')) {
      for (final attribute in ['data-src', 'data-lazy-src', 'data-original', 'src']) {
        final value = absoluteUrl(chapterRemoteId, image.attributes[attribute] ?? '');
        final uri = Uri.tryParse(value);
        if (uri == null || uri.host != Uri.parse(_base).host || value.startsWith('data:')) continue;
        final path = uri.path.toLowerCase();
        if (path.contains('/uploads/') || RegExp(r'\.(jpe?g|png|webp|gif)$').hasMatch(path)) {
          if (!urls.contains(value)) urls.add(value);
          break;
        }
      }
    }
    if (urls.isEmpty) throw const AppFailure('لم أجد صفحات هذا الفصل في Olympus Staff.');
    return urls;
  }

  bool _isChapterUrl(String href, String remoteId) {
    final uri = Uri.tryParse(href);
    if (uri == null || uri.host != Uri.parse(_base).host) return false;
    final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    if (parts.length < 2) return false;
    final lower = href.toLowerCase();
    final hasNumber = _chapterNumber(href, '') != null;
    final hasChapterWord = lower.contains('chapter') || lower.contains('الفصل') || lower.contains('-ch-');
    if (!hasNumber && !hasChapterWord) return false;

    if (parts[0].toLowerCase() == 'series') {
      return parts.length >= 3 && parts[1].toLowerCase() == remoteId.toLowerCase();
    }
    if (parts[0].toLowerCase() == 'manga') {
      final slug = parts[1].toLowerCase();
      final base = remoteId.toLowerCase();
      return slug.startsWith('$base-') || slug == base;
    }
    return false;
  }

  String? _chapterNumber(String href, String text) {
    final value = '$href $text';
    for (final pattern in [
      RegExp(r'chapter[-_ ]?(\d+(?:\.\d+)?)', caseSensitive: false),
      RegExp(r'الفصل[-_ ]?(\d+(?:\.\d+)?)'),
      RegExp(r'/([0-9]+(?:\.\d+)?)/?(?:\?|$)'),
      RegExp(r'(?:^|[^0-9])(\d+(?:\.\d+)?)(?:\D|$)'),
    ]) {
      final match = pattern.firstMatch(value);
      if (match != null) return match.group(1) ?? match.group(2);
    }
    return null;
  }

  List<Manga> _parseMangaGrid(dynamic document) {
    final results = <Manga>[];
    final seen = <String>{};
    for (final link in document.querySelectorAll('a[href]')) {
      final href = absoluteUrl(_base, link.attributes['href'] ?? '');
      final uri = Uri.tryParse(href);
      if (uri == null || uri.host != Uri.parse(_base).host) continue;
      final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
      final seriesIndex = parts.indexOf('series');
      final mangaIndex = parts.indexOf('manga');
      final index = seriesIndex >= 0 ? seriesIndex : mangaIndex;
      if (index < 0 || index + 1 >= parts.length) continue;
      final slug = parts[index + 1];
      if (_isChapterUrl(href, slug) || !seen.add(slug)) continue;
      final title = cleanText(link.text.isNotEmpty ? link.text : (link.attributes['title'] ?? slug));
      if (title.isEmpty) continue;
      final cover = imageUrl(_base, link.parent?.querySelector('img'));
      results.add(Manga(sourceId: id, remoteId: slug, title: title, remoteCoverUrl: cover.isEmpty ? null : cover));
    }
    return results;
  }

  Future<Manga?> _directSlugSearch(String query) async {
    var slug = query.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.isEmpty) return null;
    for (final url in ['$_base/series/$slug', '$_base/manga/$slug/']) {
      try {
        final document = await _document(url);
        final title = cleanText(document.querySelector('h1, .author-info-title h6, .title')?.text ?? '');
        if (title.isEmpty) continue;
        final cover = imageUrl(_base, document.querySelector('img[alt="Manga Image"], img.shadow-sm, .text-right img, .summary_image img, .profile-manga img'));
        return Manga(sourceId: id, remoteId: slug, title: title, remoteCoverUrl: cover.isEmpty ? null : cover);
      } catch (_) {}
    }
    return null;
  }

  Future<dynamic> _document(String url, {Map<String, String>? headers}) async {
    try {
      final response = await _http.getText(url, options: Options(headers: {'Accept-Language': 'ar;q=1.0', ...?headers}));
      final body = response.data;
      if (body == null || body.isEmpty) throw AppFailure.parsing();
      return html_parser.parse(body);
    } on DioException catch (e) {
      throw AppFailure.network(e);
    } on FormatException catch (e) {
      throw AppFailure.parsing(e);
    }
  }

  int _maxPage(dynamic document) {
    final values = document.querySelectorAll('.pagination a, ul.pagination a.page-link').map((a) => int.tryParse(cleanText(a.text))).whereType<int>().toList();
    return values.isEmpty ? 1 : values.reduce((a, b) => a > b ? a : b);
  }

  String _fullInfoValue(dynamic document, String label) {
    for (final info in document.querySelectorAll('.full-list-info')) {
      if ((info.querySelector('small')?.text ?? '').contains(label)) {
        final values = info.querySelectorAll('small');
        if (values.length > 1) return cleanText(values[1].text);
      }
    }
    return '';
  }

  String _chapterTitle(String text, String number) => text.replaceFirst(RegExp('^الفصل\\s*${RegExp.escape(number)}\\s*[:.\\-]?\\s*'), '').trim();
}
