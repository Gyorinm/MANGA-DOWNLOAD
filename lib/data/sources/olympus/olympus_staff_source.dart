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
      } catch (_) {
        // Try the next URL pattern.
      }
    }

    throw const AppFailure('لم أجد هذه المانجا في Olympus Staff.');
  }

  @override
  Future<List<Chapter>> chapters(
    String remoteId, {
    String language = 'ar',
  }) async {
    final all = <String, Chapter>{};
    final candidates = [
      '$_base/series/$remoteId',
      '$_base/manga/$remoteId/',
      '$_base/manga/$remoteId',
    ];

    Future<void> parsePage(
      dynamic document,
      int fallbackIndex,
      String baseUrl,
    ) async {
      for (final link in document.querySelectorAll('a[href]')) {
        final href = absoluteUrl(baseUrl, link.attributes['href'] ?? '');
        if (href.isEmpty || href == baseUrl) continue;
        if (!_looksLikeChapterLink(remoteId, href)) continue;

        final number = _extractChapterNumber(href, link.text);
        if (number == null || number.isEmpty) continue;

        final chapterTitle = cleanText(link.text);
        final parent = link.parent;
        final paid =
            parent?.classes.any((c) => c.toLowerCase().contains('lock')) == true;

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

    for (final baseUrl in candidates) {
      try {
        final firstDocument = await _document(baseUrl);
        await parsePage(firstDocument, 0, baseUrl);

        final maxPage = _maxPage(firstDocument).clamp(1, 100);
        for (var page = 2; page <= maxPage; page++) {
          final pageUrl = '$baseUrl?page=$page';
          try {
            final document = await _document(pageUrl);
            final before = all.length;
            await parsePage(document, page, baseUrl);
            if (all.length == before) break;
          } catch (_) {
            break;
          }
        }
      } catch (_) {
        // Try the next candidate URL pattern.
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
      final candidates = <String>[
        image.attributes['src'] ?? '',
        image.attributes['data-src'] ?? '',
        image.attributes['data-lazy-src'] ?? '',
        image.attributes['srcset'] ?? '',
      ];

      String? picked;
      for (final candidate in candidates) {
        final cleaned = candidate.trim();
        if (cleaned.isEmpty || cleaned.startsWith('data:')) continue;
        final resolved = absoluteUrl(chapterRemoteId, cleaned);
        if (resolved.isEmpty) continue;
        final uri = Uri.tryParse(resolved);
        if (uri == null) continue;
        final path = uri.path.toLowerCase();
        final looksLikeImage = path.endsWith('.jpg') ||
            path.endsWith('.jpeg') ||
            path.endsWith('.png') ||
            path.endsWith('.webp') ||
            path.endsWith('.gif');
        if (looksLikeImage || path.contains('/uploads/')) {
          picked = resolved;
          break;
        }
      }

      if (picked == null || picked.isEmpty) continue;
      if (!urls.contains(picked)) urls.add(picked);
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
      if (uri == null || uri.host != Uri.parse(_base).host) continue;

      final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
      final index = parts.indexOf('series');
      final mangaIndex = parts.indexOf('manga');
      final slugIndex = index >= 0 ? index + 1 : (mangaIndex >= 0 ? mangaIndex + 1 : -1);
      if (slugIndex < 0 || slugIndex >= parts.length) continue;

      final slug = parts[slugIndex];
      if (slug.isEmpty || !seen.add(slug)) continue;
      if (_looksLikeChapterSlug(slug)) continue;

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

    final candidates = [
      '$_base/series/$slug',
      '$_base/manga/$slug/',
      '$_base/manga/$slug',
    ];

    for (final url in candidates) {
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
      } catch (_) {
        // Try the next candidate.
      }
    }

    return null;
  }

  String _slugFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    final index = parts.indexOf('series');
    final mangaIndex = parts.indexOf('manga');
    final slugIndex = index >= 0 ? index + 1 : (mangaIndex >= 0 ? mangaIndex + 1 : -1);
    if (slugIndex >= 0 && slugIndex < parts.length) return parts[slugIndex];
    return parts.isEmpty ? '' : parts.last;
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

  bool _looksLikeChapterLink(String remoteId, String href) {
    final uri = Uri.tryParse(href);
    if (uri == null || uri.host != Uri.parse(_base).host) return false;

    final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return false;

    final lower = href.toLowerCase();
    final hasChapterToken = lower.contains('chapter') ||
        lower.contains('الفصل') ||
        lower.contains('/chapter-') ||
        lower.contains('/الفصل-');

    if (hasChapterToken) {
      final anySeriesMatch = parts.length >= 2 &&
          parts[0].toLowerCase() == 'series' &&
          parts[1].toLowerCase() == remoteId.toLowerCase();
      final anyMangaMatch = parts.length >= 2 &&
          parts[0].toLowerCase() == 'manga' &&
          _slugMatches(parts[1], remoteId);
      return anySeriesMatch || anyMangaMatch;
    }

    final chapterNum = _extractChapterNumber(href, '');
    if (chapterNum != null && chapterNum.isNotEmpty) {
      final seriesMatch = parts.length >= 3 &&
          parts[0].toLowerCase() == 'series' &&
          parts[1].toLowerCase() == remoteId.toLowerCase();
      final mangaMatch = parts.length >= 2 &&
          parts[0].toLowerCase() == 'manga' &&
          _slugMatches(parts[1], remoteId);
      return seriesMatch || mangaMatch;
    }

    return false;
  }

  bool _looksLikeChapterSlug(String value) {
    final lower = value.toLowerCase();
    return lower.contains('chapter') ||
        lower.contains('الفصل') ||
        lower.contains('-ch-') ||
        lower.contains('-chapter-') ||
        RegExp(r'^[0-9]+(?:[.][0-9]+)?$').hasMatch(lower);
  }

  bool _slugMatches(String actual, String remoteId) {
    final a = actual.toLowerCase();
    final b = remoteId.toLowerCase();
    return a == b || a.replaceAll(RegExp(r'[^a-z0-9]+'), '-') == b;
  }

  String? _extractChapterNumber(String href, String text) {
    final source = '$href $text'.toLowerCase();
    final patterns = [
      RegExp(r'chapter[-_ ]?(\d+(?:[.][\d]+)?)'),
      RegExp(r'الفصل[-_ ]?(\d+(?:[.][\d]+)?)'),
      RegExp(r'/([0-9]+(?:[.][\d]+)?)/?$'),
      RegExp(r'(^|[^\d])(\d+(?:[.][\d]+)?)\s*(?:\)|$)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(source);
      if (match == null) continue;
      final value = match.group(1) ?? match.group(2);
      if (value != null && value.isNotEmpty) return value;
    }

    return null;
  }
}
