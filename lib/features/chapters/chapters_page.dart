import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/entities/chapter.dart';
import '../../domain/entities/manga.dart';
import '../../providers.dart';
import '../reader/reader_page.dart';
import '../shared/widgets.dart';

/// قائمة الفصول: تعمل من قاعدة البيانات المحلية، فتظهر كاملة دون إنترنت.
class ChaptersPage extends ConsumerWidget {
  const ChaptersPage({super.key, required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapters = ref.watch(localChaptersProvider(manga.key));

    return Scaffold(
      appBar: AppBar(
        title: Text(manga.title, maxLines: 1),
        actions: [
          IconButton(
            tooltip: 'حذف المانهوا من الجهاز',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: chapters.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const ErrorNotice(message: 'تعذّر قراءة الفصول.'),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              headline: 'لا فصول بعد',
              body: 'ارجع إلى صفحة المانهوا واضغط «حمّل المانهوا كاملة».',
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (_, i) => _ChapterTile(manga: manga, chapter: list[i]),
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('حذف من الجهاز'),
        content: const Text(
          'ستُحذف كل الفصول والصور المحمّلة. يمكنك تنزيلها لاحقًا من جديد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    ref.read(downloadManagerProvider).cancelManga(manga.key);
    await ref.read(libraryRepositoryProvider).removeManga(manga.key);
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _ChapterTile extends ConsumerWidget {
  const _ChapterTile({required this.manga, required this.chapter});

  final Manga manga;
  final Chapter chapter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloading = chapter.status == ChapterStatus.downloading;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        chapter.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: chapter.isReadable ? AppTheme.textPrimary : AppTheme.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: downloading
            ? LinearProgressIndicator(value: chapter.progress, minHeight: 3)
            : Text(
                chapter.status.label,
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
      ),
      trailing: _trailing(ref),
      onTap: chapter.isReadable
          ? () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReaderPage(manga: manga, chapter: chapter),
                ),
              )
          : null,
    );
  }

  Widget _trailing(WidgetRef ref) {
    return switch (chapter.status) {
      ChapterStatus.downloaded =>
        const Icon(Icons.check_circle, color: AppTheme.accent, size: 20),
      ChapterStatus.downloading || ChapterStatus.queued => IconButton(
          icon: const Icon(Icons.close, size: 20),
          tooltip: 'إلغاء',
          onPressed: () =>
              ref.read(downloadManagerProvider).cancel(chapter.key),
        ),
      _ => IconButton(
          icon: const Icon(Icons.download_outlined, size: 20),
          tooltip: 'تحميل هذا الفصل',
          onPressed: () => ref.read(downloadManagerProvider).enqueueChapters(
                manga: manga,
                chapters: [chapter],
              ),
        ),
    };
  }
}
