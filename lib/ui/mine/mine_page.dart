import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api/download_service.dart';
import '../../api/favorite_playlist_service.dart';
import '../../models/song.dart';
import '../../models/playlist.dart';
import '../../providers/player_provider.dart';
import '../common/mini_player.dart';
import '../common/song_list_tile.dart';
import '../../l10n/app_localizations.dart';
import '../common/song_cover.dart';
import '../categories/playlist_detail_page.dart';

final downloadedSongsProvider = FutureProvider.autoDispose<List<Song>>((
  ref,
) async {
  return ref.read(downloadServiceProvider).getDownloadedSongs();
});

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
        toolbarHeight: 0,
        automaticallyImplyLeading: false,
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
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _RecentList(),
                _DownloadList(),
                _FavoritePlaylistList(),
              ],
            ),
          ),
          const MiniPlayer(),
        ],
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
        return ListView.builder(
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
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text('Error: $e')),
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
        return ListView.builder(
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
                  await ref
                      .read(downloadServiceProvider)
                      .deleteDownload(song.id);
                  ref.invalidate(downloadedSongsProvider);
                },
              ),
              onTap: () =>
                  ref.read(playerProvider.notifier).logQueue(songs, index),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text('Error: $e')),
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
        return ListView.builder(
          itemCount: playlists.length,
          itemBuilder: (context, index) {
            final playlist = playlists[index];
            return _FavoritePlaylistTile(playlist: playlist);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text('Error: $e')),
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
      subtitle: playlist.count != null ? Text('${playlist.count}') : null,
      trailing: IconButton(
        icon: const Icon(Icons.favorite),
        onPressed: () async {
          await ref
              .read(favoritePlaylistServiceProvider)
              .toggleFavorite(playlist);
          ref.invalidate(favoritePlaylistsProvider);
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
}
