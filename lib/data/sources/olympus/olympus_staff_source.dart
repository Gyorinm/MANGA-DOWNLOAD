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
    final candidates = [
      '$_base/series/$remoteId',
      '$_base/manga/$remoteId/',
      '$_base/manga/$remoteId',
    ];

    for (final url in candidates) {
      try {
        final document = await _document(url);
        final title = cleanText(
          document.querySelector('h1, .author-info-title h6, .title')?.text ??
              remoteId,
        );
        if (title.isEmpty) continue;

        final cover = imageUrl(
          _base,
          document.querySelector(
            'img[alt="Manga Image"], img.shadow-sm, .text-right img, .summary_image img, .profile-manga img',
          ),
        );

        final paragraphs = document
            .querySelectorAll('p')
            .map((p) => cleanText(p.text))
            .where((text) => text.length > 30 && !text.contains('http'))
            .toList();

        return Manga(
          sourceId: id,
          remoteId: remoteId,
          title: title,
          description: paragraphs.isEmpty ? '' : paragraphs.first,
          author: _fullInfoValue(document, 'الرسام'),
          status: detectStatus(cleanText(document.body?.text ?? '')),
          remoteCoverUrl: cover.isEmpty ? null : cover,
        );
      } catch (_) {}
    }

    throw const AppFailure('لم أجد هذه المانجا في Olympus Staff.');
  }

  @override
  Future<List<Chapter>> chapters(
    String remoteId, {
    String language = 'ar',
  }) async {
    final firstUrls = [
      '$_base/series/$remoteId',
      '$_base/manga/$remoteId/',
      '$_base/manga/$remoteId',
    ];

    final all = <String, Chapter>{};

    for (final firstUrl in firstUrls) {
      try {
        final firstDocument = await _document(firstUrl);
        _collectChapterLinks(
          firstDocument,
          firstUrl,
          remoteId,
          language,
          all,
          0,
        );

        final maxPage = _maxPage(firstDocument).clamp(1, 100);
        for (var page = 2; page <= maxPage; page++) {
          final before = all.length;
          final pageDocument = await _document('$firstUrl?page=$page');
          _collectChapterLinks(
            pageDocument,
            firstUrl,
            remoteId,
            language,
            all,
            page,
          );
          if (all.length == before) break;
        }
      } catch (_) {}
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

  void _collectChapterLinks(
    dynamic document,
    String baseUrl,
    String remoteId,
    String language,
    Map<String, Chapter> out,
    int fallbackIndex,
  ) {
    for (final link in document.querySelectorAll('a[href]')) {
      final href = _chapterUrlFromLink(link, baseUrl);
      if (href == null || !_looksLikeChapterFor(remoteId, href)) continue;

      final number = _chapterNumberFromHref(href, link.text);
      if (number == null || number.isEmpty) continue;

      final title = cleanText(link.text);
      final paid = link.parent?.classes.any(
            (c) => c.toLowerCase().contains('lock'),
          ) ==
          true;

      out[href] = Chapter(
        mangaKey: '$id::$remoteId',
        remoteId: href,
        number: number,
        title: paid && title.isEmpty
            ? 'الفصل $number (مدفوع)'
            : _chapterTitle(title, number),
        language: language,
        sortIndex: fallbackIndex,
        pageCount: 0,
      );
    }
  }

  @override
  Future<List<String>> pageUrls(String chapterRemoteId) async {
    final document = await _document(
      chapterRemoteId,
      headers: {'Referer': '$_base/'},
    );

    final urls = <String>[];
    for (final image in document.querySelectorAll('img')) {
      for (final attribute in [
        'data-src',
        'data-lazy-src',
        'data-original',
        'src',
      ]) {
        final value = absoluteUrl(chapterRemoteId, image.attributes[attribute] ?? '');
        final uri = Uri.tryParse(value);
        if (uri == null) continue;
        if (uri.host != Uri.parse(_base).host &&
            uri.host != 'www.${Uri.parse(_base).host}') {
          continue;
        }
        if (value.startsWith('data:')) continue;

        final path = uri.path.toLowerCase();
        if (path.contains('/uploads/') ||
            RegExp(r'\.(jpe?g|png|webp|gif|avif)$').hasMatch(path)) {
          if (!urls.contains(value)) urls.add(value);
          break;
        }
      }
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

    for (final link in document.querySelectorAll('a[href]')) {
      final href = absoluteUrl(_base, link.attributes['href'] ?? '');
      if (href.isEmpty) continue;

      final uri = Uri.tryParse(href);
      if (uri == null) continue;

      final host = uri.host;
      if (host != Uri.parse(_base).host && host != 'www.${Uri.parse(_base).host}') {
        continue;
      }

      final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
      final seriesIndex = parts.indexOf('series');
      final mangaIndex = parts.indexOf('manga');
      final index = seriesIndex >= 0 ? seriesIndex : mangaIndex;
      if (index < 0 || index + 1 >= parts.length) continue;

      final slug = parts[index + 1];
      if (slug.isEmpty || !seen.add(slug)) continue;

      final title = cleanText(
        link.text.isNotEmpty ? link.text : (link.attributes['title'] ?? slug),
      );
      if (title.isEmpty) continue;

      final cover = imageUrl(_base, link.parent?.querySelector('img'));

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
    final slug = _slugify(query);
    if (slug.isEmpty) return null;

    for (final url in [
      '$_base/series/$slug',
      '$_base/manga/$slug/',
      '$_base/manga/$slug',
    ]) {
      try {
        final document = await _document(url);
        final title = cleanText(
          document.querySelector('h1, .author-info-title h6, .title')?.text ?? '',
        );
        if (title.isEmpty) continue;

        final cover = imageUrl(
          _base,
          document.querySelector(
            'img[alt="Manga Image"], img.shadow-sm, .text-right img, .summary_image img, .profile-manga img',
          ),
        );

        return Manga(
          sourceId: id,
          remoteId: slug,
          title: title,
          remoteCoverUrl: cover.isEmpty ? null : cover,
        );
      } catch (_) {}
    }

    return null;
  }

  String _slugify(String value) {
    final slug = value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return slug.replaceAll(RegExp(r'^-+|-+$'), '');
  }

  String? _chapterUrlFromLink(dynamic link, String baseUrl) {
    final keys = ['href', 'data-href', 'data-url'];
    for (final key in keys) {
      final raw = link.attributes[key]?.trim() ?? '';
      if (raw.isEmpty) continue;
      final resolved = absoluteUrl(baseUrl, raw);
      if (resolved.isEmpty) continue;
      final uri = Uri.tryParse(resolved);
      if (uri == null) continue;
      final host = uri.host;
      if (host != Uri.parse(_base).host && host != 'www.${Uri.parse(_base).host}') {
        continue;
      }
      return resolved;
    }
    return null;
  }

  bool _looksLikeChapterFor(String remoteId, String href) {
    final uri = Uri.tryParse(href);
    if (uri == null) return false;

    final host = uri.host;
    if (host != Uri.parse(_base).host && host != 'www.${Uri.parse(_base).host}') {
      return false;
    }

    final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return false;

    final lowerParts = parts.map((part) => part.toLowerCase()).toList();
    final seriesIndex = lowerParts.indexOf('series');
    final mangaIndex = lowerParts.indexOf('manga');
    final sectionIndex = seriesIndex >= 0 ? seriesIndex : mangaIndex;
    if (sectionIndex < 0) return false;
    if (sectionIndex + 1 >= parts.length) return false;

    final slug = parts[sectionIndex + 1].toLowerCase();
    final expected = remoteId.toLowerCase();
    final sameSlug = slug == expected ||
        slug.startsWith('$expected-') ||
        slug.startsWith('${expected}_') ||
        slug.startsWith('${expected}/');
    if (!sameSlug) return false;

    if (sectionIndex + 2 >= parts.length) return false;
    final tail = lowerParts.sublist(sectionIndex + 2).join('/');

    final chapterToken = tail.contains('chapter') ||
        tail.contains('الفصل') ||
        tail.contains('ch-') ||
        RegExp(r'/(\d+(?:[.]\d+)?)$').hasMatch('/$tail') ||
        RegExp(r'(^|/)(chapter|الفصل)[-_]?(\d+(?:[.]\d+)?)').hasMatch('/$tail');

    return chapterToken;
  }

  String? _chapterNumberFromHref(String href, String text) {
    final normalized = _normalizeArabicDigits('$href $text');
    final patterns = [
      RegExp(r'(?:chapter|الفصل)[-_\s]*(\d+(?:[.]\d+)?)', caseSensitive: false),
      RegExp(r'/(\d+(?:[.]\d+)?)(?:/)?(?:\?|$)'),
      RegExp(r'(?<!\d)(\d+(?:[.]\d+)?)(?!\d)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(normalized);
      if (match == null) continue;
      final value = match.group(1);
      if (value != null && value.isNotEmpty) return value;
    }

    return null;
  }

  String _normalizeArabicDigits(String value) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    return value.split('').map((char) {
      final index = arabic.indexOf(char);
      return index >= 0 ? index.toString() : char;
    }).join();
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
          RegExp('^الفصل\\s*' + RegExp.escape(number) + '\\s*[:.\\-]?\\s*'),
          '',
        )
        .trim();
    return cleaned;
  }
}
