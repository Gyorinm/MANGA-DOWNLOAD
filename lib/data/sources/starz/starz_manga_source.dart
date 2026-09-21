import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:maktaba/core/http/http_client.dart';
import 'package:maktaba/core/utils/result.dart';
import 'package:maktaba/domain/entities/chapter.dart';
import 'package:maktaba/domain/entities/manga.dart';
import 'package:maktaba/data/sources/manga_source.dart';
import 'package:maktaba/data/sources/html_source_utils.dart';

class StarzMangaSource implements MangaSource {
  StarzMangaSource(this._http);

  final HttpClient _http;
  static const _base = 'https://starzmanga.com';

  @override
  String get id => 'starz';

  @override
  String get displayName => 'Mangastarz';

  @override
  List<String> get languages => const ['ar'];

  @override
  Map<String, String> get imageHeaders => const {
        'Referer': 'https://starzmanga.com/',
      };

  @override
  Future<List<Manga>> search(String query, {int page = 1}) async {
    final text = query.trim();
    final direct = await _directSlugSearch(text);
    if (direct != null) return <Manga>[direct];

    final encoded = Uri.encodeQueryComponent(text);
    final pageNumber = page < 1 ? 1 : page;

    final urls = <String>[
      '$_base/?s=$encoded&post_type=wp-manga&paged=$pageNumber',
      '$_base/?s=$encoded&post_type=wp-manga',
      '$_base/manga/?s=$encoded',
    ];

    for (final url in urls) {
      try {
        final document = await _document(url);
        final results = _parseMangaGrid(document);
        if (results.isNotEmpty) return results;
      } catch (_) {
        // Try the next public search form used by the site.
      }
    }

    return const <Manga>[];
    return const <Manga>[];
  }

  @override
  Future<Manga> details(String remoteId) async {
    final candidates = [
      '$_base/manga/$remoteId/',
      '$_base/comics/$remoteId/',
      '$_base/manhwa/$remoteId/',
      '$_base/$remoteId/',
    ];

    for (final url in candidates) {
      final document = await _document(url);
      if (!_looksLikeDetail(document)) continue;

      final cover = imageUrl(
        _base,
        document.querySelector('.summary_image img, .profile-manga img'),
      );

      final title = cleanText(
        document.querySelector('.post-title h1, h1.entry-title, .manga-title')?.text ??
            remoteId,
      );

      final description = cleanText(
        document.querySelector('.description-summary p, .summary__content p')?.text ??
            document.querySelector('.description-summary, .summary__content')?.text ??
            '',
      );

      final author = _metaValue(document, ['الكاتب', 'Author']);
      final status = detectStatus(cleanText(document.body?.text ?? ''));

      return Manga(
        sourceId: id,
        remoteId: _slugFromUrl(url),
        title: title,
        description: description,
        author: author,
        status: status,
        remoteCoverUrl: cover.isEmpty ? null : cover,
      );
    }

    throw const AppFailure('لم أجد هذه المانجا في Mangastarz.');
  }

  @override
  Future<List<Chapter>> chapters(
    String remoteId, {
    String language = 'ar',
  }) async {
    final url = '$_base/manga/$remoteId/';
    final document = await _document(url);
    final chapters = <Chapter>[];
    final seen = <String>{};

    for (final link in document.querySelectorAll('a[href]')) {
      final href = absoluteUrl(url, link.attributes['href'] ?? '');
      if (href.isEmpty || !seen.add(href)) continue;

      final uri = Uri.tryParse(href);
      if (uri == null || uri.host != Uri.parse(_base).host) continue;

      final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
      if (parts.length < 3 ||
          parts[0] != 'manga' ||
          parts[1] != remoteId) {
        continue;
      }

      final number =
          firstChapterNumber(link.text) ??
          (RegExp(r'^(\\d+(?:[.][\\d]+)?)$').firstMatch(parts.last)?.group(1)) ??
          chapterNumberFromUrl(href);
      if (number == null || number.isEmpty) continue;

      chapters.add(
        Chapter(
          mangaKey: '$id::$remoteId',
          remoteId: href,
          number: number,
          title: _chapterTitle(cleanText(link.text), number),
          language: language,
          sortIndex: 0,
        ),
      );
    }

    chapters.sort(
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
    final document = await _document(chapterRemoteId);
    final urls = <String>[];

    for (final image in document.querySelectorAll('img')) {
      final src = imageUrl(chapterRemoteId, image);
      if (src.isEmpty || src.startsWith('data:')) continue;

      final uri = Uri.tryParse(src);
      if (uri == null) continue;
      if (!uri.host.endsWith('.starzmanga.com')) continue;
      if (!uri.path.contains('/manga/')) continue;

      if (!urls.contains(src)) urls.add(src);
    }

    if (urls.isEmpty) {
      throw const AppFailure('لم أجد صفحات هذا الفصل في Mangastarz.');
    }

    return urls;
  }

  Future<dynamic> _document(String url) async {
    try {
      final response = await _http.getText(
        url,
        options: Options(
          headers: const {'Accept-Language': 'ar,en;q=0.9'},
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

  bool _looksLikeDetail(dynamic document) =>
      document.querySelector(
        '.summary_image, .listing-chapters_wrap, h1.entry-title, .post-title h1',
      ) != null;

  List<Manga> _parseMangaGrid(dynamic document) {
    final results = <Manga>[];
    final seen = <String>{};

    // Madara's card classes vary between pages; manga URLs are stable.
    for (final link in document.querySelectorAll('a[href]')) {
      final href = absoluteUrl(_base, link.attributes['href'] ?? '');
      if (href.isEmpty) continue;

      final uri = Uri.tryParse(href);
      if (uri == null || uri.host != Uri.parse(_base).host) continue;

      final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
      final index = parts.indexOf('manga');
      if (index < 0 || index + 1 >= parts.length) continue;

      final slug = parts[index + 1];
      if (slug.isEmpty || !seen.add(slug)) continue;

      final title = cleanText(
        link.text.isNotEmpty
            ? link.text
            : (link.attributes['title'] ?? link.attributes['aria-label'] ?? slug),
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
    var slug = query.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    while (slug.startsWith('-')) slug = slug.substring(1);
    while (slug.endsWith('-')) slug = slug.substring(0, slug.length - 1);
    if (slug.isEmpty) return null;
    try {
      final document = await _document('$_base/manga/$slug/');
      if (!_looksLikeDetail(document)) return null;
      final title = cleanText(document.querySelector('.post-title h1, h1.entry-title, .manga-title')?.text ?? '');
      if (title.isEmpty) return null;
      final cover = imageUrl(_base, document.querySelector('.summary_image img, .profile-manga img'));
      return Manga(sourceId: id, remoteId: slug, title: title, remoteCoverUrl: cover.isEmpty ? null : cover);
    } catch (_) {
      return null;
    }
  }

  String _slugFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    final index = parts.indexWhere(
      (part) => part == 'manga' || part == 'comics' || part == 'manhwa',
    );
    if (index >= 0 && index + 1 < parts.length) return parts[index + 1];
    return parts.last;
  }

  String _metaValue(dynamic document, List<String> labels) {
    for (final item in document.querySelectorAll('.post-content_item')) {
      final heading = cleanText(item.querySelector('.summary-heading')?.text ?? '');
      if (labels.any((label) => heading.contains(label))) {
        return cleanText(item.querySelector('.summary-content')?.text ?? '');
      }
    }
    return '';
  }

  String _chapterTitle(String text, String number) {
    var title = text
        .replaceFirst(
          RegExp('^الفصل\\\\s*' + RegExp.escape(number) + '\\\\s*[:.\\\\-]?\\\\s*'),
          '',
        )
        .trim();
    if (title == text) {
      title = text
          .replaceFirst(
            RegExp('^' + RegExp.escape(number) + '\\\\s*[:.\\\\-]?\\\\s*'),
            '',
          )
          .trim();
    }
    return title;
  }
}
