import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'dart:async';
import '../../models/playlist.dart';
import '../../providers/player_provider.dart';
import '../../api/image_cache_service.dart';
import '../common/mini_player.dart';
import 'playlist_detail_page.dart';
import '../../l10n/app_localizations.dart';

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).browse,
          style: const TextStyle(
            fontFamily: 'Playfair Display',
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Theme.of(context).primaryColor,
          tabs: [
            Tab(text: AppLocalizations.of(context).albums),
            Tab(text: AppLocalizations.of(context).playlists),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _CategoryGrid(type: 'album'),
                _CategoryGrid(type: 'playlist'),
              ],
            ),
          ),
          const MiniPlayer(),
        ],
      ),
    );
  }
}

class _CategoryGrid extends ConsumerStatefulWidget {
  final String type;
  const _CategoryGrid({required this.type});

  @override
  ConsumerState<_CategoryGrid> createState() => _CategoryGridState();
}

class _CategoryGridState extends ConsumerState<_CategoryGrid> {
  static const _pageSize = 20;
  static const _loadMoreTriggerExtent = 600.0;
  final ScrollController _scrollController = ScrollController();
  Timer? _scrollDebounce;
  List<Playlist> _items = [];
  int _currentPage = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
    _scrollController.addListener(_onScroll);
  }

  Future<List<Playlist>> _fetchByType(int page) {
    final service = ref.read(fysgServiceProvider);
    switch (widget.type) {
      case 'album':
        return service.getAlbums(page: page);
      case 'playlist':
        return service.getPlaylists(page: page);
      default:
        return Future.value(const <Playlist>[]);
    }
  }

  Future<void> _fetchInitialData() async {
    List<Playlist> items = [];
    try {
      items = await _fetchByType(0);
    } catch (e) {
      print('Error fetching ${widget.type}: $e');
    }

    if (!mounted) return;
    setState(() {
      _items = items;
      _isLoading = false;
      _hasMore = items.length >= _pageSize;
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) return;
    if (_scrollController.position.extentAfter > _loadMoreTriggerExtent) return;
    if (_scrollDebounce?.isActive ?? false) return;
    _scrollDebounce = Timer(const Duration(milliseconds: 120), _loadMore);
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;
    setState(() {
      _isLoadingMore = true;
    });

    final nextPage = _currentPage + 1;
    List<Playlist> items = [];

    try {
      items = await _fetchByType(nextPage);
    } catch (e) {
      print('Error loading more ${widget.type}: $e');
    }

    if (!mounted) return;
    setState(() {
      _items.addAll(items);
      _currentPage = nextPage;
      _isLoadingMore = false;
      _hasMore = items.length >= _pageSize;
    });
  }

  @override
  void dispose() {
    _scrollDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return MasonryGridView.count(
      controller: _scrollController,
      cacheExtent: 800,
      padding: const EdgeInsets.all(16),
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      itemCount: _items.length + (_isLoadingMore ? 2 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Center(child: CircularProgressIndicator());
        }
        final item = _items[index];
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PlaylistDetailPage(playlist: item),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      image: item.cover != null
                          ? DecorationImage(
                              image: CachedNetworkImageProvider(
                                item.cover!,
                                headers: ImageCacheService.headers,
                              ),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: item.cover == null
                        ? const Center(
                            child: Icon(
                              Icons.music_note,
                              size: 40,
                              color: Colors.grey,
                            ),
                          )
                        : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    item.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
