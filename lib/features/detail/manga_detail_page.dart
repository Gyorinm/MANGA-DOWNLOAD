import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/entities/chapter.dart';
import '../../domain/entities/manga.dart';
import '../../providers.dart';
import '../chapters/chapters_page.dart';
import '../shared/widgets.dart';

/// صفحة المانهوا: الغلاف، الاسم، عدد الفصول، وزر تحميلها كاملة.
class MangaDetailPage extends ConsumerWidget {
  const MangaDetailPage({super.key, required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapters = ref.watch(mangaChaptersProvider(manga));

    return Scaffold(
      appBar: AppBar(title: Text(manga.title, maxLines: 1)),
      body: chapters.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorNotice(
          message: 'تعذّر جلب الفصول من المصدر.',
          onRetry: () => ref.invalidate(mangaChaptersProvider(manga)),
        ),
        data: (list) => _Body(manga: manga, chapters: list),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.manga, required this.chapters});

  final Manga manga;
  final List<Chapter> chapters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = chapters
        .where((c) => c.status != ChapterStatus.downloaded)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: CoverImage(
                localPath: manga.localCoverPath,
                remoteUrl: manga.remoteCoverUrl,
                sourceId: manga.sourceId,
                title: manga.title,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(manga.title,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  _MetaLine(
                    label: 'المصدر',
                    value: ref
                            .watch(sourceRegistryProvider)
                            .byId(manga.sourceId)
                            ?.displayName ??
                        manga.sourceId,
                  ),
                  if (manga.author.isNotEmpty)
                    _MetaLine(label: 'المؤلف', value: manga.author),
                  if (manga.status.isNotEmpty)
                    _MetaLine(label: 'الحالة', value: manga.status),
                  _MetaLine(label: 'الفصول', value: '${chapters.length}'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: chapters.isEmpty || remaining == 0
              ? null
              : () => _startDownload(context, ref),
          child: Text(
            remaining == 0 && chapters.isNotEmpty
                ? 'كل الفصول محمّلة'
                : 'حمّل المانهوا كاملة ($remaining فصلًا)',
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: chapters.isEmpty
              ? null
              : () => _openChapterPicker(context, ref),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: AppTheme.textPrimary,
            side: const BorderSide(color: AppTheme.line),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('اختيار فصول محدّدة'),
        ),
        if (manga.description.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('القصة', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(manga.description,
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    );
  }

  Future<void> _openChapterPicker(BuildContext context, WidgetRef ref) async {
    // ChaptersPage تقرأ من قاعدة البيانات المحلية حتى تستطيع تحديث حالة
    // الفصل وإعادة المحاولة. نتيجة البحث ليست محفوظة بعد، لذلك كان زر
    // «اختيار فصول محددة» يفتح قائمة فارغة سابقًا.
    final saved = await ref.read(libraryRepositoryProvider).addToLibrary(
          manga,
          chapters,
        );
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChaptersPage(manga: saved)),
    );
  }

  Future<void> _startDownload(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(downloadManagerProvider).enqueueManga(
          manga: manga,
          chapters: chapters,
        );
    messenger.showSnackBar(
      const SnackBar(content: Text('أُضيفت إلى المكتبة وبدأ التحميل')),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$label: $value',
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
      ),
    );
  }
}
