import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/sources/manga_source.dart';
import '../../providers.dart';
import '../shared/delete_manga.dart';
import '../shared/widgets.dart';
import 'add_source_sheet.dart';

/// شاشة اختيار المواقع: المستخدم يحدد أين يبحث التطبيق وأين ينزّل.
class SourcesPage extends ConsumerWidget {
  const SourcesPage({super.key});

  static const _languageNames = {
    'ar': 'العربية',
    'en': 'الإنجليزية',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourceRegistryProvider).all;
    final enabled = ref.watch(enabledSourcesProvider);
    final notifier = ref.read(enabledSourcesProvider.notifier);
    final active =
        sources.where((source) => enabled.contains(source.id)).toList();
    final available =
        sources.where((source) => !enabled.contains(source.id)).toList();
    final lastOne = active.length == 1;

    return Scaffold(
      appBar: AppBar(title: const Text('مصادر التحميل')),
      floatingActionButton: available.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showAddSourceSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('إضافة موقع'),
            ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              'اختر المواقع التي تريد البحث فيها والتحميل منها. '
              'يمكنك إضافة المواقع المضمّنة في التطبيق أو تعطيلها لاحقًا. '
              'ما حُمّل سابقًا يبقى في مكتبتك دون اتصال.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const Divider(),
          if (active.isNotEmpty)
            SectionTitle(
              'المواقع المفعّلة',
              trailing: Text(
                '${active.length}',
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
          for (final source in active) ...[
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Text(
                source.displayName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _describe(source),
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                ),
              ),
              secondary: IconButton(
                tooltip: 'حذف ما حُمّل من ${source.displayName}',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () =>
                    _deleteDownloads(context, ref, source.id, source.displayName),
              ),
              value: true,
              onChanged: lastOne
                  ? null
                  : (value) => notifier.setEnabled(source.id, value),
            ),
            const Divider(),
          ],
          if (active.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('لم يتم تفعيل أي موقع. أضف موقعًا للبدء.'),
            ),
          if (lastOne)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'يبقى موقع واحد مفعّلًا دائمًا. فعّل موقعًا آخر قبل تعطيل هذا الموقع.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  String _describe(MangaSource source) {
    if (source.languages.isEmpty) return 'موقع مضمّن في التطبيق';

    final names = source.languages
        .map((language) => _languageNames[language] ?? language);

    return 'اللغات: ${names.join('، ')}';
  }
}

/// يحذف كل المانهوا المحمّلة من مصدر واحد.
Future<void> _deleteDownloads(
  BuildContext context,
  WidgetRef ref,
  String sourceId,
  String sourceName,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(libraryRepositoryProvider);
  final owned =
      (await repo.library()).where((m) => m.sourceId == sourceId).toList();

  if (owned.isEmpty) {
    messenger.showSnackBar(
      SnackBar(content: Text('لا شيء محمّل من $sourceName')),
    );
    return;
  }
  if (!context.mounted) return;

  final ok = await confirmDialog(
    context,
    title: 'حذف كل ما حُمّل من $sourceName',
    body:
        'ستُحذف المانهوا المحمّلة منه (${owned.length}) بفصولها وصورها من الجهاز.',
  );
  if (!ok) return;

  final manager = ref.read(downloadManagerProvider);
  for (final manga in owned) {
    manager.cancelManga(manga.key);
    await repo.removeManga(manga.key);
  }
  messenger.showSnackBar(
    SnackBar(content: Text('حُذف ما حُمّل من $sourceName')),
  );
}
