import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_provider.dart';
import 'home/home_page.dart';
import 'categories/categories_page.dart';
import 'search/search_page.dart';
import 'mine/mine_page.dart';
import '../l10n/app_localizations.dart';
import 'common/mini_player.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    HomePage(),
    CategoriesPage(),
    SearchPage(),
    MinePage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(playerProvider.notifier).restoreCachedQueue();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 退到后台/被挂起时保存播放进度，保证下次冷启动可续播
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      ref.read(playerProvider.notifier).persistPlaybackStateNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(index: _currentIndex, children: _pages),
            ),
            // 全局唯一的 MiniPlayer，避免四个 Tab 各持一份
            const MiniPlayer(),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_filled),
              label: AppLocalizations.of(context).home,
            ),
            NavigationDestination(
              icon: const Icon(Icons.library_music_outlined),
              selectedIcon: const Icon(Icons.library_music),
              label: AppLocalizations.of(context).browse,
            ),
            NavigationDestination(
              icon: const Icon(Icons.search),
              label: AppLocalizations.of(context).search,
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: AppLocalizations.of(context).mine,
            ),
          ],
        ),
      ),
    );
  }
}
