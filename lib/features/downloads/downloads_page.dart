import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/storage/file_storage.dart';
import '../../domain/entities/chapter.dart';
import '../../download/download_models.dart';
import '../../providers.dart';
import '../shared/widgets.dart';

/// متابعة الطابور: ما يجري الآن، وما ينتظر، وما توقّف.
class DownloadsPage extends ConsumerWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('التحميلات'),
        actions: [
          IconButton(
            tooltip: 'إخفاء المنتهية',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: () {
              ref.read(downloadManagerProvider).clearFinished();
              ref.invalidate(downloadsProvider);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const _StorageSummary(),
          const Divider(),
          Expanded(
            child: downloads.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) =>
                  const ErrorNotice(message: 'تعذّر عرض حالة التحميلات.'),
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyState(
                    headline: 'لا تحميلات جارية',
                    body: 'ابدأ تحميل مانهوا وستتابع تقدّمها هنا فصلًا بفصل.',
                  );
                }
                final sorted = [...items]..sort(
                    (a, b) => (b.isActive ? 1 : 0).compareTo(a.isActive ? 1 : 0),
                  );
                return ListView.separated(
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, i) => _DownloadTile(progress: sorted[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageSummary extends ConsumerWidget {
  const _StorageSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(libraryRevisionProvider);
    final future = ref.watch(libraryRepositoryProvider).totalSizeOnDisk();

    return FutureBuilder<int>(
      future: future,
      builder: (_, snapshot) {
        final size = snapshot.data ?? 0;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              const Icon(Icons.sd_storage_outlined,
                  size: 18, color: AppTheme.textMuted),
              const SizedBox(width: 8),
              Text(
                'المساحة المستعملة: ${FileStorage.formatBytes(size)}',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DownloadTile extends ConsumerWidget {
  const _DownloadTile({required this.progress});

  final DownloadProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(
        progress.mangaTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              progress.message ??
                  'الفصل ${progress.chapterNumber} — '
                      '${progress.done}/${progress.total} صفحة',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            if (progress.isActive) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(value: progress.ratio, minHeight: 3),
            ],
          ],
        ),
      ),
      trailing: progress.status == ChapterStatus.failed
          ? IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'إعادة المحاولة',
              onPressed: () => _retry(ref),
            )
          : progress.isActive
              ? IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'إلغاء',
                  onPressed: () =>
                      ref.read(downloadManagerProvider).cancel(progress.chapterKey),
                )
              : const Icon(Icons.check_circle,
                  color: AppTheme.accent, size: 20),
    );
  }

  Future<void> _retry(WidgetRef ref) async {
    final repo = ref.read(libraryRepositoryProvider);
    final manga = await repo.findLocal(progress.mangaKey);
    if (manga == null) return;
    final chapters = await repo.localChapters(progress.mangaKey);
    final target =
        chapters.where((c) => c.key == progress.chapterKey).toList();
    if (target.isEmpty) return;
    await ref
        .read(downloadManagerProvider)
        .enqueueChapters(manga: manga, chapters: target);
  }
}
