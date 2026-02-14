import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api/recently_played_service.dart';
import '../../api/download_service.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../common/mini_player.dart';
import '../../l10n/app_localizations.dart';
import '../../api/image_cache_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

final downloadedSongsProvider = FutureProvider.autoDispose<List<Song>>((ref) async {
  return ref.read(downloadServiceProvider).getDownloadedSongs();
});

class MinePage extends ConsumerStatefulWidget {
  const MinePage({super.key});

  @override
  ConsumerState<MinePage> createState() => _MinePageState();
}

class _MinePageState extends ConsumerState<MinePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).mine, style: const TextStyle(fontFamily: 'Playfair Display', fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: AppLocalizations.of(context).history),
            Tab(text: AppLocalizations.of(context).downloaded),
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
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final song = songs[index];
            return ListTile(
              leading: song.cover != null 
                  ? CachedNetworkImage(
                      imageUrl: song.cover!,
                      httpHeaders: ImageCacheService.headers,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                  )
                  : const Icon(Icons.music_note),
              title: Text(
                song.name, 
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold)
              ),
              subtitle: Text(
                song.artist ?? 'Unknown',
                maxLines: 2,
                overflow: TextOverflow.ellipsis
              ),
              onTap: () => ref.read(playerProvider.notifier).logQueue(songs, index),
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
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final song = songs[index];
            return ListTile(
              leading: song.cover != null 
                  ? CachedNetworkImage(
                      imageUrl: song.cover!,
                      httpHeaders: ImageCacheService.headers,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                  )
                  : const Icon(Icons.file_download_done),
              title: Text(
                song.name, 
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold)
              ),
              subtitle: Text(
                song.artist ?? 'Downloaded',
                maxLines: 2,
                overflow: TextOverflow.ellipsis
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                   await ref.read(downloadServiceProvider).deleteDownload(song.id);
                   ref.invalidate(downloadedSongsProvider);
                },
              ),
              onTap: () => ref.read(playerProvider.notifier).logQueue(songs, index),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text('Error: $e')),
    );
  }
}
