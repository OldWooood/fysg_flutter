import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../home/home_page.dart'; // for provider
import '../common/mini_player.dart';
import '../../l10n/app_localizations.dart';
import '../../api/image_cache_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class RecentlyPlayedPage extends ConsumerWidget {
  const RecentlyPlayedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentlyPlayedProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).recentlyPlayed),
      ),
      body: Column(
        children: [
          Expanded(
            child: recentAsync.when(
              data: (songs) {
                if (songs.isEmpty) {
                  return Center(child: Text(AppLocalizations.of(context).noHistory));
                }
                return ListView.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    // Reverse index to show newest first if the list isn't already sorted? 
                    // Service returns newest first usually.
                    return ListTile(
                      leading: song.cover != null
                          ? CachedNetworkImage(
                              imageUrl: song.cover!,
                              httpHeaders: ImageCacheService.headers,
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                          )
                          : const Icon(Icons.music_note, size: 40),
                      title: Text(
                        song.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold)
                      ),
                      subtitle: Text(
                        song.artist ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis
                      ),
                      onTap: () {
                        ref.read(playerProvider.notifier).logQueue(songs, index);
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text('Error: $e')),
            ),
          ),
          const MiniPlayer(),
        ],
      ),
    );
  }
}
