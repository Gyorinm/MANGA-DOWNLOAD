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

  @override String get id => 'olympus';
  @override String get displayName => 'Olympus Staff (Team-X)';
  @override List<String> get languages => const ['ar'];
  @override Map<String, String> get imageHeaders => const {'Referer': 'https://olympustaff.com/'};

  @override
  Future<List<Manga>> search(String query, {int page = 1}) async {
    final direct = await _directSlugSearch(query);
    if (direct != null) return [direct];
    final url = '$_base/?search=${Uri.encodeQueryComponent(query.trim())}&page=${page < 1 ? 1 : page}';
    try { return _parseMangaGrid(await _document(url)); } catch (_) { return const []; }
  }

  @override
  Future<Manga> details(String remoteId) async {
    for (final url in ['$_base/series/$remoteId', '$_base/manga/$remoteId/', '$_base/manga/$remoteId']) {
      try {
        final doc = await _document(url);
        final title = cleanText(doc.querySelector('h1, .author-info-title h6, .title')?.text ?? remoteId);
        if (title.isEmpty) continue;
        final cover = imageUrl(_base, doc.querySelector('img[alt="Manga Image"], img.shadow-sm, .text-right img, .summary_image img, .profile-manga img'));
        final description = doc.querySelectorAll('p').map((p) => cleanText(p.text)).firstWhere((v) => v.length > 30 && !v.contains('http'), orElse: () => '');
        return Manga(sourceId: id, remoteId: remoteId, title: title, description: description, status: detectStatus(cleanText(doc.body?.text ?? '')), remoteCoverUrl: cover.isEmpty ? null : cover);
      } catch (_) {}
    }
    throw const AppFailure('لم أجد هذه المانجا في Olympus Staff.');
  }

  @override
  Future<List<Chapter>> chapters(String remoteId, {String language = 'ar'}) async {
    final found = <String, Chapter>{};
    for (final baseUrl in ['$_base/series/$remoteId', '$_base/manga/$remoteId/', '$_base/manga/$remoteId']) {
      try {
        final doc = await _document(baseUrl);
        _collect(doc, baseUrl, remoteId, language, found, 0);
        final max = _maxPage(doc).clamp(1, 100);
        for (var page = 2; page <= max; page++) {
          final before = found.length;
          _collect(await _document('$baseUrl?page=$page'), baseUrl, remoteId, language, found, page);
          if (found.length == before) break;
        }
      } catch (_) {}
    }
    final list = found.values.toList()..sort((a, b) => chapterSortNumber(a.number).compareTo(chapterSortNumber(b.number)));
    return [for (var i = 0; i < list.length; i++) Chapter(mangaKey: list[i].mangaKey, remoteId: list[i].remoteId, number: list[i].number, title: list[i].title, language: list[i].language, sortIndex: i, pageCount: list[i].pageCount)];
  }

  void _collect(dynamic doc, String base, String remoteId, String language, Map<String, Chapter> out, int index) {
    for (final link in doc.querySelectorAll('a[href]')) {
      final href = absoluteUrl(base, link.attributes['href'] ?? '');
      if (!_isChapter(href, remoteId)) continue;
      final number = _chapterNumber(href, link.text);
      if (number == null) continue;
      final text = cleanText(link.text);
      final paid = link.parent?.classes.any((c) => c.toLowerCase().contains('lock')) == true;
      out[href] = Chapter(mangaKey: '$id::$remoteId', remoteId: href, number: number, title: paid && text.isEmpty ? 'الفصل $number (مدفوع)' : _chapterTitle(text, number), language: language, sortIndex: index, pageCount: 0);
    }
  }

  @override
  Future<List<String>> pageUrls(String chapterRemoteId) async {
    final doc = await _document(chapterRemoteId, headers: {'Referer': '$_base/'});
    final urls = <String>[];
    for (final img in doc.querySelectorAll('img')) {
      for (final attr in ['data-src', 'data-lazy-src', 'data-original', 'src']) {
        final value = absoluteUrl(chapterRemoteId, img.attributes[attr] ?? '');
        final uri = Uri.tryParse(value);
        if (uri == null || uri.host != Uri.parse(_base).host || value.startsWith('data:')) continue;
        final path = uri.path.toLowerCase();
        if (path.contains('/uploads/') || RegExp(r'\.(jpe?g|png|webp|gif)$').hasMatch(path)) { if (!urls.contains(value)) urls.add(value); break; }
      }
    }
    if (urls.isEmpty) throw const AppFailure('لم أجد صفحات هذا الفصل في Olympus Staff.');
    return urls;
  }

  bool _isChapter(String href, String remoteId) {
    final uri = Uri.tryParse(href);
    if (uri == null || uri.host != Uri.parse(_base).host) return false;
    final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return false;
    final lower = href.toLowerCase();
    final token = lower.contains('chapter') || lower.contains('الفصل') || RegExp(r'/\d+(?:\.\d+)?/?$').hasMatch(lower);
    if (!token) return false;
    if (parts[0].toLowerCase() == 'series' && parts.length >= 2) return parts[1].toLowerCase() == remoteId.toLowerCase();
    if (parts[0].toLowerCase() == 'manga' && parts.length >= 2) {
      final slug = parts[1].toLowerCase();
      final base = remoteId.toLowerCase();
      return slug == base || slug.startsWith('$base-chapter-') || slug.startsWith('${base}-chapter-') || slug.startsWith('$base-الفصل-');
    }
    return false;
  }

  String? _chapterNumber(String href, String text) {
    final value = '$href $text';
    for (final r in [RegExp(r'chapter[-_ ]?(\d+(?:\.\d+)?)', caseSensitive: false), RegExp(r'الفصل[-_ ]?(\d+(?:\.\d+)?)'), RegExp(r'/([0-9]+(?:\.\d+)?)/?(?:\?|$)'), RegExp(r'(?:^|[^0-9])(\d+(?:\.\d+)?)(?:\D|$)')]) {
      final m = r.firstMatch(value);
      if (m != null) return m.group(1) ?? m.group(2);
    }
    return null;
  }

  List<Manga> _parseMangaGrid(dynamic doc) {
    final result = <Manga>[]; final seen = <String>{};
    for (final link in doc.querySelectorAll('a[href]')) {
      final href = absoluteUrl(_base, link.attributes['href'] ?? ''); final uri = Uri.tryParse(href);
      if (uri == null || uri.host != Uri.parse(_base).host) continue;
      final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
      final seriesIndex = parts.indexOf('series');
      final mangaIndex = parts.indexOf('manga');
      final i = seriesIndex >= 0 ? seriesIndex : mangaIndex;
      if (i < 0 || i + 1 >= parts.length || _isChapter(href, parts[i + 1])) continue;
      final slug = parts[i + 1]; if (!seen.add(slug)) continue;
      final title = cleanText(link.text.isNotEmpty ? link.text : (link.attributes['title'] ?? slug)); if (title.isEmpty) continue;
      final cover = imageUrl(_base, link.parent?.querySelector('img'));
      result.add(Manga(sourceId: id, remoteId: slug, title: title, remoteCoverUrl: cover.isEmpty ? null : cover));
    }
    return result;
  }

  Future<Manga?> _directSlugSearch(String query) async {
    var slug = query.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    slug = slug.replaceAll(RegExp(r'^-+|-+$'), ''); if (slug.isEmpty) return null;
    for (final url in ['$_base/series/$slug', '$_base/manga/$slug/']) {
      try { final doc = await _document(url); final title = cleanText(doc.querySelector('h1, .author-info-title h6, .title')?.text ?? ''); if (title.isNotEmpty) { final cover = imageUrl(_base, doc.querySelector('img[alt="Manga Image"], img.shadow-sm, .text-right img, .summary_image img, .profile-manga img')); return Manga(sourceId: id, remoteId: slug, title: title, remoteCoverUrl: cover.isEmpty ? null : cover); } } catch (_) {}
    }
    return null;
  }

  Future<dynamic> _document(String url, {Map<String, String>? headers}) async {
    try { final response = await _http.getText(url, options: Options(headers: {'Accept-Language': 'ar;q=1.0', ...?headers})); final body = response.data; if (body == null || body.isEmpty) throw AppFailure.parsing(); return html_parser.parse(body); }
    on DioException catch (e) { throw AppFailure.network(e); } on FormatException catch (e) { throw AppFailure.parsing(e); }
  }

  int _maxPage(dynamic doc) { final values = doc.querySelectorAll('.pagination a, ul.pagination a.page-link').map((a) => int.tryParse(cleanText(a.text))).whereType<int>().toList(); return values.isEmpty ? 1 : values.reduce((a, b) => a > b ? a : b); }
  String _chapterTitle(String text, String number) => text.replaceFirst(RegExp('^الفصل\\s*${RegExp.escape(number)}\\s*[:.\\-]?\\s*'), '').trim();
}
