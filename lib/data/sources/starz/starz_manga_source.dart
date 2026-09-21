import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import '../../../core/http/http_client.dart';
import '../../../core/utils/result.dart';
import '../../../domain/entities/chapter.dart';
import '../../../domain/entities/manga.dart';
import '../manga_source.dart';
import '../html_source_utils.dart';

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
    final encoded = Uri.encodeQueryComponent(query.trim());
    final pageNumber = page < 1 ? 1 : page;
    final url =
        '$_base/?s=$encoded&post_type=wp-manga&paged=' + pageNumber.toString();
    final document = await _document(url);
    return _parseMangaGrid(document);
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

    void addChapter({
      required String href,
      required String text,
    }) {
      final absolute = absoluteUrl(url, href);
      if (absolute.isEmpty || !seen.add(absolute)) return;

      final number = firstChapterNumber(text) ?? chapterNumberFromUrl(absolute);
      if (number == null || number.isEmpty) return;

      chapters.add(
        Chapter(
          mangaKey: '$id::$remoteId',
          remoteId: absolute,
          number: number,
          title: _chapterTitle(text, number),
          language: language,
          sortIndex: 0,
        ),
      );
    }

    for (final li in document.querySelectorAll(
      '.listing-chapters_wrap li, li.wp-manga-chapter',
    )) {
      final link = li.querySelector('a[href]');
      if (link == null) continue;
      addChapter(
        href: link.attributes['href'] ?? '',
        text: cleanText(link.text),
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

    for (final image in document.querySelectorAll(
      '.reading-content img, .page-break img',
    )) {
      final src = imageUrl(chapterRemoteId, image);
      if (src.isEmpty || src.startsWith('data:')) continue;
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

    for (final card in document.querySelectorAll(
      'div.page-item-detail.manga, div.c-tabs-item__content, div.row.c-tabs-item__content, div.c-image-hover',
    )) {
      final link = card.querySelector(
        '.post-title a[href], .item-thumb a[href], a[href*="/manga/"]',
      );
      if (link == null) continue;

      final href = absoluteUrl(_base, link.attributes['href'] ?? '');
      if (href.isEmpty) continue;

      final slug = _slugFromUrl(href);
      if (slug.isEmpty || !seen.add(slug)) continue;

      final title = cleanText(
        card.querySelector('.post-title a, h3 a, [class*="post-title"] a')?.text ??
            link.attributes['title'] ??
            slug,
      );
      if (title.isEmpty) continue;

      final cover = imageUrl(
        _base,
        card.querySelector('.item-thumb img, img.img-responsive, img'),
      );

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
