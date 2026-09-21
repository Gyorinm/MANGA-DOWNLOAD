import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/storage/file_storage.dart';
import 'data/local/app_database.dart';
import 'data/sources/custom/custom_source_store.dart';
import 'providers.dart';

/// الإقلاع: نفتح القرص وقاعدة البيانات قبل رسم أي شيء، ثم نحقنهما في الشجرة.
/// هكذا تبقى بقية التطبيق متزامنة ولا تحتاج انتظارًا داخل الشاشات.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = await FileStorage.create();
  final database = await AppDatabase.open();
  final prefs = await SharedPreferences.getInstance();
  final customStore = CustomSourceStore(prefs, const FlutterSecureStorage());
  final customSources = await customStore.loadAll();

  runApp(
    ProviderScope(
      overrides: [
        fileStorageProvider.overrideWithValue(storage),
        databaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(prefs),
        customSourceStoreProvider.overrideWithValue(customStore),
        initialCustomSourcesProvider.overrideWithValue(customSources),
      ],
      child: const MaktabaApp(),
    ),
  );
}
