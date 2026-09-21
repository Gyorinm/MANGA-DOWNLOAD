import 'package:html/dom.dart';

/// أدوات مشتركة للمصادر التي تعتمد على صفحات HTML.
String absoluteUrl(String baseUrl, String raw) {
  final value = raw.trim();
  if (value.isEmpty || value.startsWith('data:')) return '';
  try {
    return Uri.parse(baseUrl).resolve(value).toString();
  } catch (_) {
    return value;
  }
}

String imageUrl(
  String baseUrl,
  Element? img, {
  List<String> attributes = const [
    'data-src',
    'data-lazy-src',
    'data-original',
    'data-url',
    'src',
  ],
}) {
  if (img == null) return '';
  for (final attribute in attributes) {
    final raw = img.attributes[attribute]?.trim() ?? '';
    if (raw.isEmpty || raw.startsWith('data:')) continue;
    final url = absoluteUrl(baseUrl, raw);
    if (url.isNotEmpty) return url;
  }
  return '';
}

String cleanText(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

String? firstChapterNumber(String text) {
  final match = RegExp(r'(?:الفصل\s*)?([0-9]+(?:[.][0-9]+)?)').firstMatch(text);
  return match?.group(1);
}

String? chapterNumberFromUrl(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  final match = RegExp(r'/([0-9]+(?:[.][0-9]+)?)/?$').firstMatch(path);
  return match?.group(1);
}

double chapterSortNumber(String value) =>
    double.tryParse(value.trim()) ?? double.infinity;

bool looksPaid(Element chapter) =>
    chapter.querySelector('.fa-lock, .lock, [class*="lock"]') != null;

String detectStatus(String text) {
  final value = text.toLowerCase();
  if (value.contains('مستمرة') || value.contains('مستمر') || value.contains('ongoing')) {
    return 'مستمرة';
  }
  if (value.contains('مكتملة') || value.contains('مكتمل') || value.contains('completed')) {
    return 'مكتملة';
  }
  if (value.contains('متوقف') || value.contains('متوقّف') || value.contains('hiatus')) {
    return 'متوقفة';
  }
  return '';
}
