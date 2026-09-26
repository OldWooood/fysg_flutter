import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../api/recently_played_service.dart' show recentSongsProvider;
import '../../utils/constants.dart';
import '../../utils/toast_utils.dart';
import '../common/error_view.dart';
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
  List<Song> _recommendedSongs = [];
  int _currentPage = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;
  bool _loadMoreError = false;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _fetchInitialData() async {
    final result = await ref
        .read(fysgServiceProvider)
        .getRecommendedSongsPaged(page: 0);

    if (!mounted) return;

    result.when(
      ok: (paged) {
        setState(() {
          _recommendedSongs = paged.items;
          _isLoading = false;
          _errorMessage = null;
          _currentPage = 0;
          _hasMore = paged.hasMore;
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
    if (_scrollController.position.extentAfter >
        AppConstants.loadMoreTriggerExtent) {
      return;
    }
    // 已有 _isLoadingMore 保护，越过阈值立即加载，避免滚动停止后才触发的迟钝感
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() {
      _isLoadingMore = true;
      _loadMoreError = false;
    });

    final nextPage = _currentPage + 1;
    final result = await ref
        .read(fysgServiceProvider)
        .getRecommendedSongsPaged(page: nextPage);

    if (!mounted) return;

    result.when(
      ok: (paged) {
        setState(() {
          _recommendedSongs.addAll(paged.items);
          _currentPage = nextPage;
          _isLoadingMore = false;
          _hasMore = paged.hasMore;
        });
      },
      err: (_) {
        setState(() {
          _isLoadingMore = false;
          _loadMoreError = true;
        });
        ToastUtils.showToast(context, AppLocalizations.of(context).loadFailed);
      },
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _fetchInitialData,
      child: CustomScrollView(
      controller: _scrollController,
      scrollCacheExtent: ScrollCacheExtent.pixels(
        AppConstants.listCacheExtent,
      ),
      slivers: [
        // 最近播放独立订阅：之前整页 watch，记一次历史就重建整个列表
        const _RecentSection(),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Text(
              AppLocalizations.of(context).recommended,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        ),

        // Error State
        if (_errorMessage != null)
          SliverToBoxAdapter(
            child: ErrorView(
              message: _errorMessage!,
              onRetry: () {
                setState(() {
                  _errorMessage = null;
                  _isLoading = true;
                });
                _fetchInitialData();
              },
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
                  if (_loadMoreError) {
                    return LoadMoreErrorFooter(onRetry: _loadMore);
                  }
                  return _isLoadingMore
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : const SizedBox(height: 16);
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
                    // 历史记录由播放成功后的 _logHistoryIfNeeded 统一刷新，
                    // 避免点击瞬间列表先重建跳动
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
    );
  }
}

/// 最近播放横滑区：独立 watch，最近列表变化只重建自己。
class _RecentSection extends ConsumerWidget {
  const _RecentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentSongsProvider);
    return SliverToBoxAdapter(
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
                            builder: (_) => const RecentlyPlayedPage(),
                          ),
                        );
                      },
                      child: Text(AppLocalizations.of(context).seeAll),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AspectRatio(
                              aspectRatio: 1,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SongCover(
                                  imageUrl: song.cover,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 240,
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
    );
  }
}
