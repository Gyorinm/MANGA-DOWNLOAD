import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/repositories/library_repository.dart';
import '../../domain/entities/manga.dart';
import '../../providers.dart';
import '../detail/manga_detail_page.dart';
import '../shared/widgets.dart';

/// البحث: استعلام واحد يُرسل إلى كل المصادر، والنتائج مجمّعة تحت اسم كل موقع.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// لا نُرسل طلبًا عند كل حرف؛ ننتظر توقّف الكتابة.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      ref.read(searchQueryProvider.notifier).state = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('بحث'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(66),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'اكتب اسم المانهوا',
                prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _controller.clear();
                          ref.read(searchQueryProvider.notifier).state = '';
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
        ),
      ),
      body: query.trim().length < 2
          ? const EmptyState(
              headline: 'ابحث في كل المصادر دفعة واحدة',
              body: 'اكتب حرفين على الأقل، وستظهر النتائج مرتّبة حسب الموقع.',
            )
          : _Results(query: query),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(searchResultsProvider(query));

    return results.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorNotice(
        message: 'تعذّر إتمام البحث. تحقّق من الشبكة.',
        onRetry: () => ref.invalidate(searchResultsProvider(query)),
      ),
      data: (groups) {
        if (groups.isEmpty) {
          return const EmptyState(
            headline: 'لا نتائج',
            body: 'جرّب كتابة الاسم بالإنجليزية أو بصيغة أقصر.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: groups.length,
          itemBuilder: (_, i) => _SourceGroup(group: groups[i]),
        );
      },
    );
  }
}

class _SourceGroup extends StatelessWidget {
  const _SourceGroup({required this.group});

  final SourceResults group;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          group.sourceName,
          trailing: Text(
            group.error == null ? '${group.items.length} نتيجة' : '',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ),
        if (group.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              group.error!,
              style: const TextStyle(color: AppTheme.textMuted),
            ),
          )
        else
          SizedBox(
            height: 250,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: group.items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _ResultCard(manga: group.items[i]),
            ),
          ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 124,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MangaDetailPage(manga: manga)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CoverImage(remoteUrl: manga.remoteCoverUrl, title: manga.title),
            const SizedBox(height: 8),
            Text(
              manga.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}
