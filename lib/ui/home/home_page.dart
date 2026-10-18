import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../api/recently_played_service.dart' show recentSongsProvider;
import '../../utils/constants.dart';
import '../../utils/paged_list_controller.dart';
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
  late final PagedListController<Song> _recommended;

  @override
  void initState() {
    super.initState();
    _recommended = PagedListController<Song>(
      fetch: (page) =>
          ref.read(fysgServiceProvider).getRecommendedSongsPaged(page: page),
      onTransientError: (error) {
        if (!mounted) return;
        ToastUtils.showAppError(context, error);
      },
    );
    _recommended.refresh();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter >
        AppConstants.loadMoreTriggerExtent) {
      return;
    }
    // 已有 isLoadingMore/hasMore 保护，越过阈值立即加载，避免滚动停止后才触发的迟钝感
    _recommended.loadMore();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _recommended.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _recommended.refresh,
      child: ListenableBuilder(
        listenable: _recommended,
        builder: (context, _) {
          final songs = _recommended.items;
          final error = _recommended.error;
          return CustomScrollView(
            controller: _scrollController,
            scrollCacheExtent: ScrollCacheExtent.pixels(
              AppConstants.listCacheExtent,
            ),
            slivers: [
              // 最近播放独立订阅：之前整页 watch，记一次历史就重建整个列表
              const _RecentSection(),

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

              // Error State（仅首屏失败整屏报错；刷新失败保留列表 + toast）
              if (error != null)
                SliverToBoxAdapter(
                  child: ErrorView(
                    message: ToastUtils.localizedAppError(context, error),
                    onRetry: _recommended.retry,
                  ),
                )
              // Loading State
              else if (_recommended.isLoading)
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
                      if (index == songs.length) {
                        if (_recommended.loadMoreError) {
                          return LoadMoreErrorFooter(
                            onRetry: _recommended.loadMore,
                          );
                        }
                        return _recommended.isLoadingMore
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            : const SizedBox(height: 16);
                      }
                      final song = songs[index];
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
                              .logQueue(songs, index);
                        },
                      );
                    },
                    childCount: songs.length + 1,
                    addAutomaticKeepAlives: false,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 最近播放横滑区：独立 watch，最近列表变化只重建自己。
class _RecentSection extends ConsumerWidget {
  const _RecentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(recentSongsProvider);
    if (songs.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                  onTap: () =>
                      ref.read(playerProvider.notifier).logQueue(songs, index),
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
      ),
    );
  }
}
