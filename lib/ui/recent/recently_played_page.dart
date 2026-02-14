import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/player_provider.dart';
import '../common/mini_player.dart';
import '../common/song_list_tile.dart';
import '../../l10n/app_localizations.dart';

class RecentlyPlayedPage extends ConsumerWidget {
  const RecentlyPlayedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentSongsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).recentlyPlayed)),
      body: Column(
        children: [
          Expanded(
            child: recentAsync.when(
              data: (songs) {
                if (songs.isEmpty) {
                  return Center(
                    child: Text(AppLocalizations.of(context).noHistory),
                  );
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
                      onTap: () {
                        ref
                            .read(playerProvider.notifier)
                            .logQueue(songs, index);
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
