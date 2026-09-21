import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// الجهة الوحيدة التي تعرف أين تسكن الملفات على القرص.
///
/// بنية المجلدات:
///   {support}/library/{mangaKey}/cover.jpg
///   {support}/library/{mangaKey}/{chapterKey}/0001.jpg
class FileStorage {
  FileStorage._(this._root);

  final Directory _root;

  static Future<FileStorage> create() async {
    final base = await getApplicationSupportDirectory();
    final root = Directory(p.join(base.path, 'library'));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return FileStorage._(root);
  }

  String get rootPath => _root.path;

  /// يحوّل أي معرّف إلى اسم ملف آمن على كل أنظمة التشغيل.
  static String safeName(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.length <= 80 ? cleaned : cleaned.substring(0, 80);
  }

  Directory mangaDir(String mangaKey) =>
      Directory(p.join(_root.path, safeName(mangaKey)));

  Directory chapterDir(String mangaKey, String chapterKey) =>
      Directory(p.join(_root.path, safeName(mangaKey), safeName(chapterKey)));

  String coverPath(String mangaKey) =>
      p.join(mangaDir(mangaKey).path, 'cover.jpg');

  /// اسم صفحة مُصفّر ليبقى الترتيب الأبجدي مطابقًا للترتيب الرقمي.
  String pagePath(String mangaKey, String chapterKey, int index, String ext) {
    final name = '${(index + 1).toString().padLeft(4, '0')}$ext';
    return p.join(chapterDir(mangaKey, chapterKey).path, name);
  }

  Future<Directory> ensure(Directory dir) async {
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<File>> readChapterPages(String mangaKey, String chapterKey) async {
    final dir = chapterDir(mangaKey, chapterKey);
    if (!await dir.exists()) return const [];
    final files = await dir
        .list()
        .where((e) => e is File && _isImage(e.path))
        .cast<File>()
        .toList();
    files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    return files;
  }

  Future<void> deleteChapter(String mangaKey, String chapterKey) async {
    final dir = chapterDir(mangaKey, chapterKey);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<void> deleteManga(String mangaKey) async {
    final dir = mangaDir(mangaKey);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// الحجم بالبايت — يُستعمل في شاشة إدارة المساحة.
  Future<int> sizeOf(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  static bool _isImage(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.jpg' || ext == '.jpeg' || ext == '.png' || ext == '.webp';
  }

  static String formatBytes(int bytes) {
    const units = ['بايت', 'ك.ب', 'م.ب', 'ج.ب'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}
