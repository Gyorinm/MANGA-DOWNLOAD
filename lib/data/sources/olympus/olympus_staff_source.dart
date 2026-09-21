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
  Map<String, String> get imageHeaders => const {
        'Referer': 'https://olympustaff.com/',
      };

  @override
  Future<List<Manga>> search(String query, {int page = 1}) async {
    final text = query.trim();
    final direct = await _directSlugSearch(text);
    if (direct != null) return <Manga>[direct];

    final encoded = Uri.encodeQueryComponent(text);
    final safePage = page < 1 ? 1 : page;
    final url = '$_base/?search=$encoded&page=$safePage';
    try {
      final document = await _document(url);
      final results = _parseMangaGrid(document);
      if (results.isNotEmpty) return results;
    } catch (_) {
      // Some requests may be blocked by the site's anti-bot/ad layer.
      // Exact-title lookup above remains available.
    }
    return const <Manga>[];
  }

  @override
  Future<Manga> details(String remoteId) async {
    final url = '$_base/series/$remoteId';
    final document = await _document(url);

    final cover = imageUrl(
      _base,
      document.querySelector(
        'img[alt="Manga Image"], img.shadow-sm, .text-right img',
      ),
    );

    final title = cleanText(
      document.querySelector('h1, .author-info-title h6, .title')?.text ??
          remoteId,
    );

    final paragraphs = document
        .querySelectorAll('p')
        .map((p) => cleanText(p.text))
        .where((text) => text.length > 30 && !text.contains('http'))
        .toList();
    final description = paragraphs.isEmpty ? '' : paragraphs.first;

    final bodyText = cleanText(document.body?.text ?? '');
    final status = detectStatus(bodyText);

    final author = _fullInfoValue(document, 'الرسام');

    return Manga(
      sourceId: id,
      remoteId: remoteId,
      title: title,
      description: description,
      author: author,
      status: status,
      remoteCoverUrl: cover.isEmpty ? null : cover,
    );
  }

  @override
  Future<List<Chapter>> chapters(
    String remoteId, {
    String language = 'ar',
  }) async {
    final firstUrl = '$_base/series/$remoteId';
    final all = <String, Chapter>{};

    Future<void> parsePage(
      dynamic document,
      int fallbackIndex,
    ) async {
      // Olympus currently exposes chapter links as /series/<id>/<number>.
      // Do not depend on page-specific CSS classes; inspect all public links.
      for (final link in document.querySelectorAll('a[href]')) {
        final href = absoluteUrl(
          firstUrl,
          link.attributes['href'] ?? '',
        );
        if (href.isEmpty || href == firstUrl) continue;

        final uri = Uri.tryParse(href);
        if (uri == null || uri.host != Uri.parse(_base).host) continue;

        final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
        if (parts.length < 3 ||
            parts[0] != 'series' ||
            parts[1] != remoteId) {
          continue;
        }

        final number =
            firstChapterNumber(link.text) ??
            (RegExp(r'^(\\d+(?:[.][\\d]+)?)$').firstMatch(parts.last)?.group(1)) ??
            chapterNumberFromUrl(href);
        if (number == null || number.isEmpty) continue;

        final chapterTitle = cleanText(link.text);
        final parent = link.parent;
        final paid =
            parent?.classes.any((c) => c.toLowerCase().contains('lock')) ==
                true;

        all[href] = Chapter(
          mangaKey: '$id::$remoteId',
          remoteId: href,
          number: number,
          title: paid && chapterTitle.isEmpty
              ? 'الفصل $number (مدفوع)'
              : _chapterTitle(chapterTitle, number),
          language: language,
          sortIndex: fallbackIndex,
          pageCount: 0,
        );
      }
    }

    final firstDocument = await _document(firstUrl);
    await parsePage(firstDocument, 0);

    final maxPage = _maxPage(firstDocument).clamp(1, 100);
    for (var page = 2; page <= maxPage; page++) {
      final pageUrl = '$firstUrl?page=$page';
      try {
        final document = await _document(pageUrl);
        final before = all.length;
        await parsePage(document, page);
        if (all.length == before) break;
      } catch (_) {
        break;
      }
    }

    final chapters = all.values.toList()
      ..sort(
        (a, b) => chapterSortNumber(a.number).compareTo(
          chapterSortNumber(b.number),
        ),
      );

    return chapters
        .asMap()
        .entries
        .map(
          (entry) => Chapter(
            mangaKey: entry.value.mangaKey,
            remoteId: entry.value.remoteId,
            number: entry.value.number,
            title: entry.value.title,
            language: entry.value.language,
            sortIndex: entry.key,
            pageCount: entry.value.pageCount,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<String>> pageUrls(String chapterRemoteId) async {
    final document = await _document(
      chapterRemoteId,
      headers: {'Referer': '$_base/'},
    );

    final urls = <String>[];
    for (final image in document.querySelectorAll('img')) {
      final src = imageUrl(chapterRemoteId, image);
      if (src.isEmpty || src.startsWith('data:')) continue;

      final uri = Uri.tryParse(src);
      if (uri == null || uri.host != Uri.parse(_base).host) continue;
      if (!uri.path.contains('/uploads/')) continue;

      if (!urls.contains(src)) urls.add(src);
    }

    if (urls.isEmpty) {
      throw const AppFailure('لم أجد صفحات هذا الفصل في Olympus Staff.');
    }

    return urls;
  }

  Future<dynamic> _document(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _http.getText(
        url,
        options: Options(
          headers: {
            'Accept-Language': 'ar,en;q=0.9',
            ...?headers,
          },
        ),
      );
      final body = response.data;
      if (body == null || body.isEmpty) throw AppFailure.parsing();
      return html_parser.parse(body);
    } on DioException catch (e) {
      throw AppFailure.network(e);
    } on FormatException catch (e) {
      throw AppFailure.parsing(e);
    }
  }

  List<Manga> _parseMangaGrid(dynamic document) {
    final results = <Manga>[];
    final seen = <String>{};

    // The site has changed card classes over time. Manga links remain stable.
    for (final link in document.querySelectorAll('a[href]')) {
      final href = absoluteUrl(_base, link.attributes['href'] ?? '');
      if (href.isEmpty) continue;

      final uri = Uri.tryParse(href);
      if (uri == null || uri.host != Uri.parse(_base).host) continue;

      final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
      final index = parts.indexOf('series');
      if (index < 0 || index + 1 >= parts.length) continue;

      final slug = parts[index + 1];
      if (slug.isEmpty || !seen.add(slug)) continue;

      final title = cleanText(
        link.text.isNotEmpty
            ? link.text
            : (link.attributes['title'] ?? slug),
      );
      if (title.isEmpty) continue;

      final parent = link.parent;
      final cover = imageUrl(_base, parent?.querySelector('img'));

      results.add(
        Manga(
          sourceId: id,
          remoteId: slug,
          title: title,
          remoteCoverUrl: cover.isEmpty ? null : cover,
        ),
      );
    }

    return results;
  }

  Future<Manga?> _directSlugSearch(String query) async {
    var slug = query.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    while (slug.startsWith('-')) slug = slug.substring(1);
    while (slug.endsWith('-')) slug = slug.substring(0, slug.length - 1);
    if (slug.isEmpty) return null;
    try {
      final document = await _document('$_base/series/$slug');
      final title = cleanText(
        document.querySelector('h1, .author-info-title h6, .title')?.text ?? '',
      );
      if (title.isEmpty) return null;
      final cover = imageUrl(
        _base,
        document.querySelector(
          'img[alt="Manga Image"], img.shadow-sm, .text-right img',
        ),
      );
      return Manga(sourceId: id, remoteId: slug, title: title, remoteCoverUrl: cover.isEmpty ? null : cover);
    } catch (_) {
      return null;
    }
  }

  String _slugFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    final index = parts.indexOf('series');
    if (index >= 0 && index + 1 < parts.length) return parts[index + 1];
    return '';
  }

  int _maxPage(dynamic document) {
    final values = document
        .querySelectorAll('ul.pagination a.page-link, .pagination a')
        .map((a) => int.tryParse(cleanText(a.text)))
        .whereType<int>()
        .toList();
    return values.isEmpty ? 1 : values.reduce((a, b) => a > b ? a : b);
  }

  String _fullInfoValue(dynamic document, String label) {
    for (final info in document.querySelectorAll('.full-list-info')) {
      final text = info.querySelector('small')?.text ?? '';
      if (text.contains(label)) {
        final values = info.querySelectorAll('small');
        if (values.length > 1) return cleanText(values[1].text);
      }
    }
    return '';
  }

  String _chapterTitle(String text, String number) {
    final cleaned = text
        .replaceFirst(
          RegExp('^الفصل\\\\s*' + RegExp.escape(number) + '\\\\s*[:.\\\\-]?\\\\s*'),
          '',
        )
        .trim();
    return cleaned;
  }
}
