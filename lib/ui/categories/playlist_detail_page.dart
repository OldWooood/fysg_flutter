import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import '../../models/playlist.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../api/image_cache_service.dart';
import '../../api/favorite_playlist_service.dart';
import '../common/mini_player.dart';
import '../common/song_list_tile.dart';
import '../../l10n/app_localizations.dart';

class PlaylistDetailPage extends ConsumerStatefulWidget {
  final Playlist playlist;

  const PlaylistDetailPage({super.key, required this.playlist});

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  static const _pageSize = 20;
  static const _loadMoreTriggerExtent = 600.0;
  final ScrollController _scrollController = ScrollController();
  Timer? _scrollDebounce;
  List<Song> _songs = [];
  int _currentPage = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _fetchInitialSongs();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) return;
    if (_scrollController.position.extentAfter > _loadMoreTriggerExtent) return;
    if (_scrollDebounce?.isActive ?? false) return;
    _scrollDebounce = Timer(const Duration(milliseconds: 120), _loadMore);
  }

  Future<void> _fetchInitialSongs() async {
    final service = ref.read(fysgServiceProvider);
    try {
      final songs = await service.getCollectionSongs(
        widget.playlist.type,
        widget.playlist.id,
        page: 0,
      );
      if (mounted) {
        setState(() {
          _songs = songs;
          _isLoading = false;
          _hasMore = songs.length >= _pageSize;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading songs: $e')));
      }
    }
  }

  Future<void> _loadMore() async {
    setState(() {
      _isLoadingMore = true;
    });

    final service = ref.read(fysgServiceProvider);
    final nextPage = _currentPage + 1;
    try {
      final songs = await service.getCollectionSongs(
        widget.playlist.type,
        widget.playlist.id,
        page: nextPage,
      );
      if (mounted) {
        setState(() {
          _songs.addAll(songs);
          _currentPage = nextPage;
          _isLoadingMore = false;
          _hasMore = songs.length >= _pageSize;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollDebounce?.cancel();
    _scrollController.dispose();
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
              child: CustomScrollView(
                controller: _scrollController,
                cacheExtent: 800,
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
                          shadows: [Shadow(color: Colors.black, blurRadius: 10)],
                        ),
                      ),
                      background: widget.playlist.cover != null
                          ? CachedNetworkImage(
                              imageUrl: widget.playlist.cover!,
                              httpHeaders: ImageCacheService.headers,
                              fit: BoxFit.cover,
                            )
                          : Container(color: Theme.of(context).primaryColor),
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
                              isFavorite ? Icons.favorite : Icons.favorite_border,
                              color: Colors.white,
                            ),
                            label: Text(
                              isFavorite
                                  ? AppLocalizations.of(context).removeFavorite
                                  : AppLocalizations.of(context).addFavorite,
                              style: const TextStyle(color: Colors.white),
                            ),
                          );
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  if (!_isLoading && _songs.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            ref
                                .read(playerProvider.notifier)
                                .logQueue(_songs, 0);
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
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_isLoading)
                    const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final song = _songs[index];
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
                                  ? Theme.of(context).primaryColor
                                  : null,
                            ),
                            subtitleStyle: const TextStyle(fontSize: 12),
                            trailing: const Icon(Icons.play_circle_outline),
                            onTap: () {
                              ref
                                  .read(playerProvider.notifier)
                                  .logQueue(_songs, index);
                            },
                          );
                        },
                        childCount: _songs.length,
                        addAutomaticKeepAlives: false,
                      ),
                    ),
                    if (_isLoadingMore)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ],
              ),
            ),
            const MiniPlayer(),
          ],
        ),
      ),
    );
  }
}
