import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../api/recently_played_service.dart' show recentSongsProvider;
import '../../utils/constants.dart';
import '../common/mini_player.dart';
import '../common/song_cover.dart';
import '../common/song_list_tile.dart';
import '../recent/recently_played_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final ScrollController _scrollController = ScrollController();
  Timer? _scrollDebounce;
  List<Song> _recommendedSongs = [];
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

  Future<void> _fetchInitialData() async {
    final result = await ref
        .read(fysgServiceProvider)
        .getRecommendedSongs(page: 0);
    
    if (!mounted) return;
    
    result.when(
      ok: (songs) {
        setState(() {
          _recommendedSongs = songs;
          _isLoading = false;
          _hasMore = songs.length >= AppConstants.defaultPageSize;
        });
      },
      err: (error) {
        setState(() {
          _isLoading = false;
          _errorMessage = error.message;
        });
      },
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) return;
    if (_scrollController.position.extentAfter > AppConstants.loadMoreTriggerExtent) {
      return;
    }
    if (_scrollDebounce?.isActive ?? false) return;
    _scrollDebounce = Timer(AppConstants.scrollDebounceMs, _loadMore);
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    final nextPage = _currentPage + 1;
    final result = await ref
        .read(fysgServiceProvider)
        .getRecommendedSongs(page: nextPage);
    
    if (!mounted) return;
    
    result.when(
      ok: (songs) {
        setState(() {
          _recommendedSongs.addAll(songs);
          _currentPage = nextPage;
          _isLoadingMore = false;
          _hasMore = songs.length >= AppConstants.defaultPageSize;
        });
      },
      err: (_) {
        setState(() => _isLoadingMore = false);
      },
    );
  }

  @override
  void dispose() {
    _scrollDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recentAsync = ref.watch(recentSongsProvider);

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              controller: _scrollController,
              cacheExtent: 800,
              slivers: [
                // Recently Played Section
                SliverToBoxAdapter(
                  child: recentAsync.when(
                    data: (songs) {
                      if (songs.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  AppLocalizations.of(context).recentlyPlayed,
                                  style: Theme.of(context).textTheme.headlineSmall,
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const RecentlyPlayedPage(),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    AppLocalizations.of(context).seeAll,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: 180,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: songs.length,
                              itemBuilder: (context, index) {
                                final song = songs[index];
                                return GestureDetector(
                                  onTap: () => ref
                                      .read(playerProvider.notifier)
                                      .logQueue(songs, index),
                                  child: Container(
                                    width: 120,
                                    margin: const EdgeInsets.only(right: 15),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        AspectRatio(
                                          aspectRatio: 1,
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: SongCover(
                                              imageUrl: song.cover,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          song.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (e, s) => const SizedBox.shrink(),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    child: Text(
                      AppLocalizations.of(context).recommended,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ),

                // Error State
                if (_errorMessage != null)
                  SliverToBoxAdapter(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.grey,
                          ),
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
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  )
                // Loading State
                else if (_isLoading)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                // Recommended List
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index == _recommendedSongs.length) {
                          return _isLoadingMore
                              ? const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              : const SizedBox(height: 100);
                        }
                        final song = _recommendedSongs[index];
                        return SongListTile(
                          key: ValueKey(song.id),
                          song: song,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 5,
                          ),
                          titleStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                          subtitleStyle: const TextStyle(fontSize: 14),
                          onTap: () {
                            ref.invalidate(recentSongsProvider);
                            ref
                                .read(playerProvider.notifier)
                                .logQueue(_recommendedSongs, index);
                          },
                        );
                      },
                      childCount: _recommendedSongs.length + 1,
                      addAutomaticKeepAlives: false,
                    ),
                  ),
              ],
            ),
          ),
          const MiniPlayer(),
        ],
      ),
    );
  }
}
