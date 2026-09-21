import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/entities/manga.dart';
import '../../providers.dart';
import '../chapters/chapters_page.dart';
import '../shared/delete_manga.dart';
import '../shared/widgets.dart';

/// الرئيسية: أغلفة ما نزّله المستخدم. تعمل دون إنترنت بالكامل.
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key, required this.onSearchTap});

  final VoidCallback onSearchTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('مكتبتي')),
      body: library.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorNotice(
          message: 'تعذّر فتح المكتبة المحلية.',
          onRetry: () => ref.invalidate(libraryProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              headline: 'المكتبة فارغة',
              body: 'ابحث عن مانهوا ونزّلها، فتظهر هنا وتُقرأ دون إنترنت.',
              action: FilledButton(
                onPressed: onSearchTap,
                child: const Text('ابحث عن مانهوا'),
              ),
            );
          }
          return _Grid(items: items);
        },
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.items});

  final List<Manga> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.52,
        crossAxisSpacing: 14,
        mainAxisSpacing: 18,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => _LibraryTile(manga: items[i]),
    );
  }
}

class _LibraryTile extends ConsumerWidget {
  const _LibraryTile({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onLongPress: () => confirmAndDeleteManga(context, ref, manga),
      onTap: () async {
        await ref.read(libraryRepositoryProvider).markOpened(manga.key);
        if (!context.mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChaptersPage(manga: manga)),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              CoverImage(
                localPath: manga.localCoverPath,
                remoteUrl: manga.remoteCoverUrl,
                sourceId: manga.sourceId,
                title: manga.title,
              ),
              if (manga.downloadedChapters < manga.totalChapters)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: manga.downloadRatio,
                    minHeight: 3,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            manga.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35),
          ),
          const SizedBox(height: 2),
          Text(
            '${manga.downloadedChapters} من ${manga.totalChapters} فصلًا',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
