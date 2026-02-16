import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home/home_page.dart';
import 'categories/categories_page.dart';
import 'search/search_page.dart';
import 'mine/mine_page.dart';
import '../l10n/app_localizations.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    HomePage(),
    CategoriesPage(),
    SearchPage(),
    MinePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        top: true,
        bottom: false,
        child: IndexedStack(index: _currentIndex, children: _pages),
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
              icon: const Icon(Icons.home),
              label: AppLocalizations.of(context).home,
            ),
            NavigationDestination(
              icon: const Icon(Icons.library_music),
              label: AppLocalizations.of(context).browse,
            ),
            NavigationDestination(
              icon: const Icon(Icons.search),
              label: AppLocalizations.of(context).search,
            ),
            NavigationDestination(
              icon: const Icon(Icons.person),
              label: AppLocalizations.of(context).mine,
            ),
          ],
        ),
      ),
    );
  }
}
