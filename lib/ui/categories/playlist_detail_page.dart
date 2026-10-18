import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/favorite_playlist_service.dart';
import '../../api/image_cache_service.dart';
import '../../l10n/app_localizations.dart';
import '../../models/playlist.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../utils/constants.dart';
import '../../utils/paged_list_controller.dart';
import '../../utils/toast_utils.dart';
import '../common/error_view.dart';
import '../common/mini_player.dart';
import '../common/song_list_tile.dart';

class PlaylistDetailPage extends ConsumerStatefulWidget {
  final Playlist playlist;

  const PlaylistDetailPage({super.key, required this.playlist});

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  final ScrollController _scrollController = ScrollController();
  late final PagedListController<Song> _songs;

  @override
  void initState() {
    super.initState();
    _songs = PagedListController<Song>(
      fetch: (page) => ref
          .read(fysgServiceProvider)
          .getCollectionSongsPaged(
            widget.playlist.type,
            widget.playlist.id,
            page: page,
          ),
      onTransientError: (error) {
        if (!mounted) return;
        ToastUtils.showAppError(context, error);
      },
    );
    _songs.refresh();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter >
        AppConstants.loadMoreTriggerExtent) {
      return;
    }
    _songs.loadMore();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _songs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentSongId = ref.watch(
      playerProvider.select((s) => s.currentSong?.id),
    );
    final favoriteAsync = ref.watch(favoritePlaylistsProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListenableBuilder(
                listenable: _songs,
                builder: (context, _) {
                  final songs = _songs.items;
                  final error = _songs.error;
                  return RefreshIndicator(
                    onRefresh: _songs.refresh,
                    child: CustomScrollView(
                      controller: _scrollController,
                      scrollCacheExtent: ScrollCacheExtent.pixels(
                        AppConstants.listCacheExtent,
                      ),
                      slivers: [
                        SliverAppBar(
                          expandedHeight: 250,
                          pinned: true,
                          flexibleSpace: FlexibleSpaceBar(
                            title: Text(
                              widget.playlist.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                shadows: [
                                  Shadow(color: Colors.black, blurRadius: 10),
                                ],
                              ),
                            ),
                            background: widget.playlist.cover != null
                                ? Hero(
                                    tag:
                                        'playlist-cover-${widget.playlist.type}-${widget.playlist.id}',
                                    child: CachedNetworkImage(
                                      imageUrl: widget.playlist.cover!,
                                      httpHeaders: ImageCacheService.headers,
                                      cacheManager:
                                          ImageCacheService.cacheManager,
                                      fit: BoxFit.cover,
                                      // 头图按显示尺寸解码，避免全分辨率 OOM
                                      memCacheWidth: 800,
                                      memCacheHeight: 500,
                                    ),
                                  )
                                : ColoredBox(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                          ),
                          actions: [
                            favoriteAsync.when(
                              data: (favorites) {
                                final isFavorite = favorites.any(
                                  (p) =>
                                      p.id == widget.playlist.id &&
                                      p.type == widget.playlist.type,
                                );
                                return TextButton.icon(
                                  onPressed: () async {
                                    await ref
                                        .read(favoritePlaylistServiceProvider)
                                        .toggleFavorite(widget.playlist);
                                    ref.invalidate(favoritePlaylistsProvider);
                                  },
                                  icon: Icon(
                                    isFavorite
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: Colors.white,
                                  ),
                                  label: Text(
                                    isFavorite
                                        ? AppLocalizations.of(
                                            context,
                                          ).removeFavorite
                                        : AppLocalizations.of(
                                            context,
                                          ).addFavorite,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                );
                              },
                              loading: () => const SizedBox.shrink(),
                              error: (_, _) => const SizedBox.shrink(),
                            ),
                          ],
                        ),
                        if (error != null)
                          SliverFillRemaining(
                            child: ErrorView(
                              message: ToastUtils.localizedAppError(
                                context,
                                error,
                              ),
                              onRetry: _songs.retry,
                            ),
                          )
                        else if (!_songs.isLoading && songs.isEmpty)
                          // 空歌单提示：之前是空白 + 100 高度占位，用户以为卡死
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: RefreshIndicator(
                              onRefresh: _songs.refresh,
                              child: ListView(
                                children: [
                                  const SizedBox(height: 120),
                                  EmptyView(
                                    message: AppLocalizations.of(
                                      context,
                                    ).emptyPlaylist,
                                  ),
                                ],
                              ),
                            ),
                          )
                        else if (!_songs.isLoading && songs.isNotEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  ref
                                      .read(playerProvider.notifier)
                                      .logQueue(songs, 0);
                                },
                                icon: const Icon(Icons.play_arrow),
                                label: Text(
                                  AppLocalizations.of(context).playAll,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (_songs.isLoading)
                          const SliverFillRemaining(
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else ...[
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final song = songs[index];
                                final isPlaying = currentSongId == song.id;

                                return SongListTile(
                                  key: ValueKey(song.id),
                                  song: song,
                                  leading: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 16,
                                    ),
                                  ),
                                  titleStyle: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isPlaying
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                                  subtitleStyle: const TextStyle(fontSize: 12),
                                  trailing: const Icon(
                                    Icons.play_circle_outline,
                                  ),
                                  onTap: () {
                                    ref
                                        .read(playerProvider.notifier)
                                        .logQueue(songs, index);
                                  },
                                );
                              },
                              childCount: songs.length,
                              addAutomaticKeepAlives: false,
                            ),
                          ),
                          if (_songs.isLoadingMore)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            ),
                          if (_songs.loadMoreError)
                            SliverToBoxAdapter(
                              child: LoadMoreErrorFooter(
                                onRetry: _songs.loadMore,
                              ),
                            ),
                          const SliverToBoxAdapter(
                            child: SizedBox(height: 100),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            const MiniPlayer(),
          ],
        ),
      ),
    );
  }
}
