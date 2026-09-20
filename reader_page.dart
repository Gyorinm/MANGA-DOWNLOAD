import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../app/theme.dart';
import '../../domain/entities/chapter.dart';
import '../../domain/entities/manga.dart';
import '../../providers.dart';
import '../shared/widgets.dart';

/// القارئ: يعرض صور القرص فقط، ولا يلمس الشبكة إطلاقًا.
///
/// الاتجاه من اليمين إلى اليسار موافق لطريقة قراءة المانهوا وللعربية معًا.
class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.manga, required this.chapter});

  final Manga manga;
  final Chapter chapter;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  late final PageController _controller =
      PageController(initialPage: widget.chapter.lastPageRead);

  List<File> _pages = const [];
  bool _loading = true;
  bool _chromeVisible = true;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _current = widget.chapter.lastPageRead;
    _load();
  }

  Future<void> _load() async {
    final storage = ref.read(fileStorageProvider);
    final files = await storage.readChapterPages(
      widget.chapter.mangaKey,
      widget.chapter.remoteId,
    );
    if (!mounted) return;
    setState(() {
      _pages = files;
      _loading = false;
    });
  }

  void _onPageChanged(int index) {
    setState(() => _current = index);
    // حفظ الموضع فورًا: القارئ قد يغلق التطبيق في أي لحظة.
    ref
        .read(libraryRepositoryProvider)
        .saveReadingPosition(widget.chapter.key, index);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_pages.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.chapter.displayName)),
        body: const EmptyState(
          headline: 'لا توجد صفحات على الجهاز',
          body: 'يبدو أن التحميل لم يكتمل. أعد تحميل هذا الفصل ثم افتحه.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => setState(() => _chromeVisible = !_chromeVisible),
            child: PhotoViewGallery.builder(
              pageController: _controller,
              itemCount: _pages.length,
              reverse: true, // من اليمين إلى اليسار
              backgroundDecoration:
                  const BoxDecoration(color: Colors.black),
              onPageChanged: _onPageChanged,
              builder: (_, i) => PhotoViewGalleryPageOptions(
                imageProvider: FileImage(_pages[i]),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3,
                filterQuality: FilterQuality.medium,
              ),
              loadingBuilder: (_, __) =>
                  const Center(child: CircularProgressIndicator()),
            ),
          ),
          if (_chromeVisible) _topBar(),
          if (_chromeVisible) _bottomBar(),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 6,
          bottom: 10,
          left: 8,
          right: 8,
        ),
        color: Colors.black.withValues(alpha: 0.72),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_forward, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Text(
                widget.chapter.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 10,
          top: 10,
          left: 20,
          right: 20,
        ),
        color: Colors.black.withValues(alpha: 0.72),
        child: Text(
          'صفحة ${_current + 1} من ${_pages.length}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
        ),
      ),
    );
  }
}
