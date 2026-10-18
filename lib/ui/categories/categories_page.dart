import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../api/image_cache_service.dart';
import '../../l10n/app_localizations.dart';
import '../../models/playlist.dart';
import '../../providers/player_provider.dart';
import '../../utils/constants.dart';
import '../../utils/paged_list_controller.dart';
import '../../utils/toast_utils.dart';
import '../common/error_view.dart';
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
  late final PagedListController<Playlist> _controller;

  @override
  void initState() {
    super.initState();
    _controller = PagedListController<Playlist>(
      fetch: (page) {
        final service = ref.read(fysgServiceProvider);
        return switch (widget.type) {
          'album' => service.getAlbumsPaged(page: page),
          'playlist' => service.getPlaylistsPaged(page: page),
          _ => Future.error(UnsupportedError('Unknown type: ${widget.type}')),
        };
      },
      onTransientError: (error) {
        if (!mounted) return;
        ToastUtils.showAppError(context, error);
      },
    );
    _controller.refresh();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter >
        AppConstants.loadMoreTriggerExtent) {
      return;
    }
    _controller.loadMore();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final items = _controller.items;
        if (_controller.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final error = _controller.error;
        if (error != null) {
          return ErrorView(
            message: ToastUtils.localizedAppError(context, error),
            onRetry: _controller.retry,
          );
        }

        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: _controller.refresh,
            child: ListView(
              children: [
                const SizedBox(height: 120),
                EmptyView(message: AppLocalizations.of(context).noResults),
              ],
            ),
          );
        }

        final placeholderColor = Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest;

        return RefreshIndicator(
          onRefresh: _controller.refresh,
          child: MasonryGridView.count(
            controller: _scrollController,
            cacheExtent: AppConstants.listCacheExtent,
            padding: const EdgeInsets.all(16),
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            itemCount:
                items.length +
                ((_controller.isLoadingMore || _controller.loadMoreError)
                    ? 1
                    : 0),
            itemBuilder: (context, index) {
              if (index >= items.length) {
                if (_controller.loadMoreError) {
                  return LoadMoreErrorFooter(onRetry: _controller.loadMore);
                }
                return const Center(child: CircularProgressIndicator());
              }
              final item = items[index];
              return RepaintBoundary(
                child: GestureDetector(
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
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
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
                                          cacheManager:
                                              ImageCacheService.cacheManager,
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
                ),
              );
            },
          ),
        );
      },
    );
  }
}
