import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/downloads/downloads_page.dart';
import '../features/library/library_page.dart';
import '../features/search/search_page.dart';
import '../providers.dart';
import 'theme.dart';

class MaktabaApp extends StatelessWidget {
  const MaktabaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مكتبة',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeShell(),
    );
  }
}

/// ثلاث وجهات فقط: المكتبة، البحث، التحميلات.
/// يُحتفظ بحالة كل تبويب عبر [IndexedStack] فلا يُعاد البحث عند التنقّل.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // استئناف ما توقّف عند آخر إغلاق، بعد اكتمال أول إطار.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(downloadManagerProvider).resumePending();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          LibraryPage(onSearchTap: () => setState(() => _index = 1)),
          const SearchPage(),
          const DownloadsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark),
            label: 'مكتبتي',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'بحث',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: 'التحميلات',
          ),
        ],
      ),
    );
  }
}
