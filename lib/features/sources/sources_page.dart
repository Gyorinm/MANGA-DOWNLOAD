import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../providers.dart';

/// شاشة اختيار المواقع: المستخدم هو من يقرّر أين يبحث وأين يحمّل.
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
    final lastOne = enabled.length == 1;

    return Scaffold(
      appBar: AppBar(title: const Text('مصادر التحميل')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              'اختر المواقع التي يبحث فيها التطبيق ويحمّل منها. '
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
                'اللغات: ${source.languages.map((l) => _languageNames[l] ?? l).join('، ')}',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
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
}
