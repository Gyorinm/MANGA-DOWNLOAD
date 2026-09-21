import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/sources/custom/komga_source.dart';
import '../../data/sources/manga_source.dart';
import '../../providers.dart';
import '../shared/delete_manga.dart';
import 'add_source_sheet.dart';

enum _SourceAction { deleteDownloads, removeSource }

/// شاشة اختيار المواقع: المستخدم هو من يقرّر أين يبحث وأين يحمّل،
/// وله أن يضيف مصادره الخاصة ويزيلها.
class SourcesPage extends ConsumerWidget {
  const SourcesPage({super.key});

  static const _languageNames = {
    'ar': 'العربية',
    'en': 'الإنجليزية',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sourcesRevisionProvider);
    final sources = ref.watch(sourceRegistryProvider).all;
    final enabled = ref.watch(enabledSourcesProvider);
    final notifier = ref.read(enabledSourcesProvider.notifier);
    final lastOne = enabled.length == 1;

    return Scaffold(
      appBar: AppBar(title: const Text('مصادر التحميل')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddSourceSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('إضافة مصدر'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              'اختر المواقع التي يبحث فيها التطبيق ويحمّل منها، أو أضف مصدرك الخاص. '
              'ما حمّلته سابقًا يبقى في مكتبتك مهما غيّرت اختيارك.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const Divider(),
          for (final source in sources) ...[
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Text(
                source.displayName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _describe(source),
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              secondary: PopupMenuButton<_SourceAction>(
                tooltip: 'خيارات ${source.displayName}',
                onSelected: (action) {
                  switch (action) {
                    case _SourceAction.deleteDownloads:
                      _deleteDownloads(
                          context, ref, source.id, source.displayName);
                    case _SourceAction.removeSource:
                      _removeSource(context, ref, source);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: _SourceAction.deleteDownloads,
                    child: Text('حذف ما حُمّل منه'),
                  ),
                  if (source is KomgaSource)
                    const PopupMenuItem(
                      value: _SourceAction.removeSource,
                      child: Text('إزالة هذا المصدر'),
                    ),
                ],
              ),
              value: enabled.contains(source.id),
              // آخر مصدر مفعّل لا يُعطَّل، حتى لا يبقى البحث بلا وجهة.
              onChanged: enabled.contains(source.id) && lastOne
                  ? null
                  : (value) => notifier.setEnabled(source.id, value),
            ),
            const Divider(),
          ],
          if (lastOne)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'يبقى مصدر واحد مفعّلًا دائمًا. فعّل مصدرًا آخر إن أردت تعطيل هذا.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  String _describe(MangaSource source) {
    if (source.languages.isNotEmpty) {
      final names = source.languages.map((l) => _languageNames[l] ?? l);
      return 'اللغات: ${names.join('، ')}';
    }
    if (source is KomgaSource) return source.config.baseUrl;
    return '';
  }
}

Future<void> _removeSource(
  BuildContext context,
  WidgetRef ref,
  MangaSource source,
) async {
  final ok = await confirmDialog(
    context,
    title: 'إزالة «${source.displayName}»',
    body: 'يُحذف المصدر من قائمتك فقط. ما حمّلته منه يبقى في مكتبتك '
        'ويُقرأ دون إنترنت.',
    confirmLabel: 'إزالة',
  );
  if (!ok) return;
  await ref.read(customSourcesControllerProvider).remove(source.id);
}

/// يحذف كل المانهوا المحمّلة من مصدر واحد، دون المساس بالمصادر الأخرى.
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
    body: 'ستُحذف المانهوا المحمّلة منه (${owned.length}) بفصولها وصورها من الجهاز.',
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
