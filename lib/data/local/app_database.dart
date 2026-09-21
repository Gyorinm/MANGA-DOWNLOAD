import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// مخطط قاعدة البيانات وترقياتها.
///
/// كُتب المخطط يدويًا بدل توليد الكود، ليبقى الانتقال بين الإصدارات صريحًا
/// ومقروءًا، وليخلو المشروع من ملفات مولّدة تحتاج build_runner.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const _fileName = 'maktaba.db';
  static const _version = 1;

  static const tableManga = 'manga';
  static const tableChapter = 'chapter';

  static Future<AppDatabase> open() async {
    final dir = await getDatabasesPath();
    final database = await openDatabase(
      p.join(dir, _fileName),
      version: _version,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createSchema,
      onUpgrade: _migrate,
    );
    return AppDatabase._(database);
  }

  static Future<void> _createSchema(Database d, int version) async {
    final batch = d.batch();

    batch.execute('''
      CREATE TABLE $tableManga (
        manga_key        TEXT PRIMARY KEY,
        source_id        TEXT NOT NULL,
        remote_id        TEXT NOT NULL,
        title            TEXT NOT NULL,
        description      TEXT NOT NULL DEFAULT '',
        author           TEXT NOT NULL DEFAULT '',
        status           TEXT NOT NULL DEFAULT '',
        remote_cover_url TEXT,
        local_cover_path TEXT,
        total_chapters   INTEGER NOT NULL DEFAULT 0,
        added_at         INTEGER NOT NULL,
        last_opened_at   INTEGER
      )
    ''');

    batch.execute('''
      CREATE TABLE $tableChapter (
        chapter_key      TEXT PRIMARY KEY,
        manga_key        TEXT NOT NULL,
        remote_id        TEXT NOT NULL,
        number           TEXT NOT NULL,
        title            TEXT NOT NULL DEFAULT '',
        language         TEXT NOT NULL DEFAULT 'ar',
        sort_index       INTEGER NOT NULL DEFAULT 0,
        page_count       INTEGER NOT NULL DEFAULT 0,
        downloaded_pages INTEGER NOT NULL DEFAULT 0,
        status           TEXT NOT NULL DEFAULT 'notDownloaded',
        last_page_read   INTEGER NOT NULL DEFAULT 0,
        published_at     INTEGER,
        FOREIGN KEY (manga_key) REFERENCES $tableManga (manga_key)
          ON DELETE CASCADE
      )
    ''');

    // فهرس الترتيب: كل استعلامات شاشة الفصول تمرّ عبره.
    batch.execute(
      'CREATE INDEX idx_chapter_manga ON $tableChapter (manga_key, sort_index)',
    );
    // فهرس الحالة: يخدم شاشة التحميلات واستئناف الطابور بعد إقلاع التطبيق.
    batch.execute(
      'CREATE INDEX idx_chapter_status ON $tableChapter (status)',
    );

    await batch.commit(noResult: true);
  }

  static Future<void> _migrate(Database d, int from, int to) async {
    // الإصدار 1 هو الأول؛ تُضاف هنا خطوات الترقية لاحقًا، خطوة لكل إصدار.
  }

  Future<void> close() => db.close();
}
