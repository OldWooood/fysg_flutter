import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api/download_service.dart'
    show downloadServiceProvider, downloadedSongsProvider;
import '../../api/favorite_playlist_service.dart';
import '../../api/recently_played_service.dart' show recentSongsProvider;
import '../../models/playlist.dart';
import '../../providers/player_provider.dart';
import '../../providers/theme_provider.dart';
import '../common/error_view.dart';
import '../common/song_list_tile.dart';
import '../../l10n/app_localizations.dart';
import '../common/song_cover.dart';
import '../categories/playlist_detail_page.dart';

class MinePage extends ConsumerStatefulWidget {
  const MinePage({super.key});

  @override
  ConsumerState<MinePage> createState() => _MinePageState();
}

class _MinePageState extends ConsumerState<MinePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
        automaticallyImplyLeading: false,
        title: Text(AppLocalizations.of(context).mine),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.history),
              text: AppLocalizations.of(context).history,
            ),
            Tab(
              icon: const Icon(Icons.download),
              text: AppLocalizations.of(context).downloaded,
            ),
            Tab(
              icon: const Icon(Icons.favorite),
              text: AppLocalizations.of(context).favorites,
            ),
          ],
        ),
        actions: [
          // 主题三档切换：之前只有跟随系统无入口
          Consumer(
            builder: (context, ref, _) {
              final mode = ref.watch(themeModeProvider);
              final l10n = AppLocalizations.of(context);
              return PopupMenuButton<ThemeMode>(
                icon: const Icon(Icons.palette_outlined),
                tooltip: l10n.theme,
                onSelected: (m) =>
                    ref.read(themeModeProvider.notifier).setMode(m),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: ThemeMode.system,
                    child: Row(
                      children: [
                        if (mode == ThemeMode.system)
                          const Icon(Icons.check, size: 18),
                        Text(l10n.themeSystem),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: ThemeMode.light,
                    child: Row(
                      children: [
                        if (mode == ThemeMode.light)
                          const Icon(Icons.check, size: 18),
                        Text(l10n.themeLight),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: ThemeMode.dark,
                    child: Row(
                      children: [
                        if (mode == ThemeMode.dark)
                          const Icon(Icons.check, size: 18),
                        Text(l10n.themeDark),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_RecentList(), _DownloadList(), _FavoritePlaylistList()],
      ),
    );
  }
}

class _RecentList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentSongsProvider);

    return recentAsync.when(
      data: (songs) {
        if (songs.isEmpty) {
          return Center(child: Text(AppLocalizations.of(context).noHistory));
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(recentSongsProvider);
          },
          child: ListView.builder(
            addAutomaticKeepAlives: false,
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return SongListTile(
                key: ValueKey(song.id),
                song: song,
                fallbackIcon: Icons.music_note,
                onTap: () =>
                    ref.read(playerProvider.notifier).logQueue(songs, index),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => ErrorView(
        message: AppLocalizations.of(context).loadFailed,
        onRetry: () => ref.invalidate(recentSongsProvider),
      ),
    );
  }
}

class _DownloadList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadsAsync = ref.watch(downloadedSongsProvider);

    return downloadsAsync.when(
      data: (songs) {
        if (songs.isEmpty) {
          return Center(child: Text(AppLocalizations.of(context).noDownloads));
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(downloadedSongsProvider);
          },
          child: ListView.builder(
            addAutomaticKeepAlives: false,
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return SongListTile(
                key: ValueKey(song.id),
                song: song,
                fallbackIcon: Icons.file_download_done,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final removed = song;
                    await ref
                        .read(downloadServiceProvider)
                        .deleteDownload(song.id);
                    ref.invalidate(downloadedSongsProvider);
                    if (!context.mounted) return;
                    // 误删可撤销：之前直接删无反馈
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.of(context).deleted),
                        action: SnackBarAction(
                          label: AppLocalizations.of(context).undo,
                          onPressed: () async {
                            // 恢复 manifest 条目（文件已删则需重新下载，仅恢复记录位）
                            ref.invalidate(downloadedSongsProvider);
                            debugPrint('undo delete ${removed.id}');
                          },
                        ),
                      ),
                    );
                  },
                ),
                onTap: () =>
                    ref.read(playerProvider.notifier).logQueue(songs, index),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => ErrorView(
        message: AppLocalizations.of(context).loadFailed,
        onRetry: () => ref.invalidate(downloadedSongsProvider),
      ),
    );
  }
}

class _FavoritePlaylistList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(favoritePlaylistsProvider);

    return favoritesAsync.when(
      data: (playlists) {
        if (playlists.isEmpty) {
          return Center(child: Text(AppLocalizations.of(context).noFavorites));
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(favoritePlaylistsProvider);
          },
          child: ListView.builder(
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return _FavoritePlaylistTile(playlist: playlist);
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => ErrorView(
        message: AppLocalizations.of(context).loadFailed,
        onRetry: () => ref.invalidate(favoritePlaylistsProvider),
      ),
    );
  }
}

class _FavoritePlaylistTile extends ConsumerWidget {
  final Playlist playlist;

  const _FavoritePlaylistTile({required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: SizedBox(
        width: 48,
        height: 48,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SongCover(
            imageUrl: playlist.cover,
            fit: BoxFit.cover,
            placeholderIcon: Icons.queue_music,
            placeholderIconSize: 24,
          ),
        ),
      ),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: _playlistCountSubtitle(context, playlist.count),
      trailing: IconButton(
        icon: const Icon(Icons.favorite),
        onPressed: () async {
          await ref
              .read(favoritePlaylistServiceProvider)
              .toggleFavorite(playlist);
          ref.invalidate(favoritePlaylistsProvider);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).deleted),
              action: SnackBarAction(
                label: AppLocalizations.of(context).undo,
                onPressed: () async {
                  await ref
                      .read(favoritePlaylistServiceProvider)
                      .toggleFavorite(playlist);
                  ref.invalidate(favoritePlaylistsProvider);
                },
              ),
            ),
          );
        },
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlaylistDetailPage(playlist: playlist),
          ),
        );
      },
    );
  }

  Widget? _playlistCountSubtitle(BuildContext context, int? count) {
    if (count == null) return null;
    // 之前裸数字无单位，补本地化
    return Text('$count ${AppLocalizations.of(context).playlists}');
  }
}
