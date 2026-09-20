import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/storage/file_storage.dart';
import 'data/local/app_database.dart';
import 'providers.dart';

/// الإقلاع: نفتح القرص وقاعدة البيانات قبل رسم أي شيء، ثم نحقنهما في الشجرة.
/// هكذا تبقى بقية التطبيق متزامنة ولا تحتاج انتظارًا داخل الشاشات.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = await FileStorage.create();
  final database = await AppDatabase.open();

  runApp(
    ProviderScope(
      overrides: [
        fileStorageProvider.overrideWithValue(storage),
        databaseProvider.overrideWithValue(database),
      ],
      child: const MaktabaApp(),
    ),
  );
}
