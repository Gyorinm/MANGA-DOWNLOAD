import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/http/http_client.dart';
import 'core/storage/file_storage.dart';
import 'data/local/app_database.dart';
import 'data/local/library_dao.dart';
import 'data/repositories/library_repository.dart';
import 'data/sources/comick/comick_source.dart';
import 'data/sources/olympus/olympus_staff_source.dart';
import 'data/sources/starz/starz_manga_source.dart';
import 'data/sources/mangadex/mangadex_source.dart';
import 'data/sources/source_registry.dart';
import 'data/sources/source_settings.dart';
import 'domain/entities/chapter.dart';
import 'domain/entities/manga.dart';
import 'download/download_manager.dart';
import 'download/download_models.dart';

/// كل التبعيات تُبنى هنا، مرة واحدة، وتُحقن نزولًا.
/// أي شاشة تقرأ ما تحتاجه فقط، فيبقى الاختبار ممكنًا باستبدال مزوّد واحد.

// ── البنية التحتية ───────────────────────────────────────────────────────

final httpClientProvider = Provider<HttpClient>((ref) {
  final client = HttpClient();
  ref.onDispose(client.close);
  return client;
});

/// تُهيّأ مرة عند الإقلاع ويُعاد استخدامها بعد ذلك.
final fileStorageProvider = Provider<FileStorage>(
  (ref) => throw UnimplementedError('يُحقن في main()'),
);

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('يُحقن في main()'),
);

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('يُحقن في main()'),
);

final daoProvider = Provider<LibraryDao>(
  (ref) => LibraryDao(ref.watch(databaseProvider)),
);

/// جميع المواقع التي يعرف التطبيق كيف يتعامل معها.
///
/// المصدر لا يقرر هل سيبحث فيه المستخدم أم لا؛ هذا القرار محفوظ في
/// [enabledSourcesProvider].
final sourceRegistryProvider = Provider<SourceRegistry>((ref) {
  final http = ref.watch(httpClientProvider);
  return SourceRegistry([
    MangaDexSource(http),
    ComicKSource(http),
    OlympusStaffSource(http),
    StarzMangaSource(http),
  ]);
});

/// المواقع التي اختار المستخدم البحث والتحميل منها.
/// مصدر واحد على الأقل يبقى مفعّلًا.
final enabledSourcesProvider =
    StateNotifierProvider<SourceSettingsNotifier, Set<String>>((ref) {
  final registry = ref.watch(sourceRegistryProvider);
  return SourceSettingsNotifier(
    ref.watch(sharedPreferencesProvider),
    registry.all.map((s) => s.id).toSet(),
  );
});

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  final repo = LibraryRepository(
    dao: ref.watch(daoProvider),
    registry: ref.watch(sourceRegistryProvider),
    storage: ref.watch(fileStorageProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final downloadManagerProvider = Provider<DownloadManager>((ref) {
  final manager = DownloadManager(
    http: ref.watch(httpClientProvider),
    storage: ref.watch(fileStorageProvider),
    dao: ref.watch(daoProvider),
    registry: ref.watch(sourceRegistryProvider),
    repository: ref.watch(libraryRepositoryProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

// ── حالة الواجهة ─────────────────────────────────────────────────────────

/// نبضة تتغيّر كلما تغيّرت المكتبة، تعتمد عليها الشاشات لإعادة الجلب.
final libraryRevisionProvider = StreamProvider<void>((ref) {
  return ref.watch(libraryRepositoryProvider).changes;
});

final libraryProvider = FutureProvider<List<Manga>>((ref) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(libraryRepositoryProvider).library();
});

final searchQueryProvider = StateProvider<String>((_) => '');

final searchResultsProvider =
    FutureProvider.family<List<SourceResults>, String>((ref, query) {
  if (query.trim().length < 2) return Future.value(const []);
  // مراقبة اختيار المستخدم تعيد البحث تلقائيًا عند إضافة موقع أو إزالته.
  final enabled = ref.watch(enabledSourcesProvider);
  return ref
      .watch(libraryRepositoryProvider)
      .searchAll(query.trim(), sourceIds: enabled);
});

final mangaChaptersProvider =
    FutureProvider.family<List<Chapter>, Manga>((ref, manga) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(libraryRepositoryProvider).chapters(manga);
});

final localChaptersProvider =
    FutureProvider.family<List<Chapter>, String>((ref, mangaKey) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(libraryRepositoryProvider).localChapters(mangaKey);
});

/// بثّ حيّ لتقدّم التحميلات، مع لقطة أولية حتى لا تبدأ الشاشة فارغة.
final downloadsProvider = StreamProvider<List<DownloadProgress>>((ref) async* {
  final manager = ref.watch(downloadManagerProvider);
  yield manager.snapshot;
  await for (final _ in manager.events) {
    yield manager.snapshot;
  }
});
