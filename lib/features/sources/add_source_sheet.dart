import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sources/manga_source.dart';
import '../../providers.dart';
import '../../app/theme.dart';

/// يفتح قائمة بالمواقع المضمّنة غير المفعّلة.
/// لا يطلب التطبيق من المستخدم عنوان خادم أو بيانات دخول؛ كل موقع هنا
/// يملك محوّلًا حقيقيًا داخل التطبيق.
Future<void> showAddSourceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    builder: (_) => const _AddSourceSheet(),
  );
}

class _AddSourceSheet extends ConsumerWidget {
  const _AddSourceSheet();

  static const _languageNames = {
    'ar': 'العربية',
    'en': 'الإنجليزية',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourceRegistryProvider).all;
    final enabled = ref.watch(enabledSourcesProvider);
    final available =
        sources.where((source) => !enabled.contains(source.id)).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: available.isEmpty
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'إضافة موقع',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'لا توجد مواقع أخرى مضمّنة وغير مفعّلة حاليًا.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('إغلاق'),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'إضافة موقع',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'اختر موقعًا ليصبح جزءًا من البحث والتحميل.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  ...available.map(
                    (source) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.language_outlined),
                      title: Text(
                        source.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(_describe(source, _languageNames)),
                      trailing: const Icon(Icons.add),
                      onTap: () async {
                        await ref
                            .read(enabledSourcesProvider.notifier)
                            .setEnabled(source.id, true);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  String _describe(
    MangaSource source,
    Map<String, String> languageNames,
  ) {
    if (source.languages.isEmpty) return 'موقع مضمّن في التطبيق';

    final names = source.languages
        .map((language) => languageNames[language] ?? language);

    return 'اللغات: ${names.join('، ')}';
  }
}
