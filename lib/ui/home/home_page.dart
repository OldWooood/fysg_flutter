import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../../models/song.dart';
import '../common/mini_player.dart';
import '../common/song_cover.dart';
import '../common/song_list_tile.dart';
import '../recent/recently_played_page.dart';
import '../../providers/player_provider.dart';
import '../../l10n/app_localizations.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  static const _pageSize = 20;
  static const _loadMoreTriggerExtent = 600.0;
  final ScrollController _scrollController = ScrollController();
  Timer? _scrollDebounce;
  List<Song> _recommendedSongs = [];
  int _currentPage = 0;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _fetchInitialData() async {
    final songs = await ref
        .read(fysgServiceProvider)
        .getRecommendedSongs(page: 0);
    if (!mounted) return;
    setState(() {
      _recommendedSongs = songs;
      _currentPage = 0;
      _hasMore = songs.length >= _pageSize;
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) return;
    if (_scrollController.position.extentAfter > _loadMoreTriggerExtent) return;
    if (_scrollDebounce?.isActive ?? false) return;
    _scrollDebounce = Timer(const Duration(milliseconds: 120), _loadMore);
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() {
      _isLoadingMore = true;
    });

    final nextPage = _currentPage + 1;
    try {
      final songs = await ref
          .read(fysgServiceProvider)
          .getRecommendedSongs(page: nextPage);
      if (!mounted) return;
      setState(() {
        _recommendedSongs.addAll(songs);
        _currentPage = nextPage;
        _isLoadingMore = false;
        _hasMore = songs.length >= _pageSize;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
      });
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
                                horizontal: 20.0,
                                vertical: 10,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    AppLocalizations.of(context).recentlyPlayed,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
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
                        horizontal: 20.0,
                        vertical: 10,
                      ),
                      child: Text(
                        AppLocalizations.of(context).recommended,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ),

                  // Recommended List
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
