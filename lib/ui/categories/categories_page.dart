import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../api/image_cache_service.dart';
import '../../l10n/app_localizations.dart';
import '../../models/playlist.dart';
import '../../providers/player_provider.dart';
import '../../utils/constants.dart';
import 'playlist_detail_page.dart';

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        automaticallyImplyLeading: false,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Theme.of(context).hintColor,
          indicatorColor: Theme.of(context).colorScheme.primary,
          tabs: [
            Tab(text: AppLocalizations.of(context).albums),
            Tab(text: AppLocalizations.of(context).playlists),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _CategoryGrid(type: 'album'),
          _CategoryGrid(type: 'playlist'),
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
  final ScrollController _scrollController = ScrollController();
  List<Playlist> _items = [];
  int _currentPage = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _fetchByType(int page) async {
    final service = ref.read(fysgServiceProvider);
    final result = switch (widget.type) {
      'album' => await service.getAlbums(page: page),
      'playlist' => await service.getPlaylists(page: page),
      _ => throw UnsupportedError('Unknown type: ${widget.type}'),
    };

    if (!mounted) return;

    result.when(
      ok: (items) {
        setState(() {
          if (page == 0) {
            _items = items;
            _isLoading = false;
          } else {
            _items.addAll(items);
            _currentPage = page;
            _isLoadingMore = false;
          }
          _hasMore = items.length >= AppConstants.defaultPageSize;
        });
      },
      err: (error) {
        setState(() {
          _errorMessage = error.message;
          _isLoading = false;
          _isLoadingMore = false;
        });
        if (page == 0) {
          debugPrint('Error fetching ${widget.type}: $error');
        }
      },
    );
  }

  Future<void> _fetchInitialData() async {
    await _fetchByType(0);
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) return;
    if (_scrollController.position.extentAfter >
        AppConstants.loadMoreTriggerExtent) {
      return;
    }
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    await _fetchByType(_currentPage + 1);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(_errorMessage!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _errorMessage = null;
                  _isLoading = true;
                });
                _fetchInitialData();
              },
              child: Text(AppLocalizations.of(context).retry),
            ),
          ],
        ),
      );
    }

    final placeholderColor = Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest;

    return MasonryGridView.count(
      controller: _scrollController,
      cacheExtent: AppConstants.listCacheExtent,
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
                  color: Colors.black.withValues(alpha: 0.08),
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
                  child: Hero(
                    tag: 'playlist-cover-${widget.type}-${item.id}',
                    child: Container(
                      decoration: BoxDecoration(
                        color: placeholderColor,
                        image: item.cover != null
                            ? DecorationImage(
                                image: CachedNetworkImageProvider(
                                  item.cover!,
                                  headers: ImageCacheService.headers,
                                  // 网格小图按 ~200px 解码，避免全分辨率解码 OOM
                                  maxWidth: 400,
                                  maxHeight: 400,
                                ),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: item.cover == null
                          ? Center(
                              child: Icon(
                                Icons.music_note,
                                size: 40,
                                color: Theme.of(context).hintColor,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
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
