import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../player/player_page.dart';
import '../player/playlist_bottom_sheet.dart';
import '../../providers/player_provider.dart';
import '../../models/song.dart';
import '../../api/image_cache_service.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final song = playerState.currentSong;

    if (song == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const PlayerPage(),
            fullscreenDialog: true,
          ),
        );
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 80),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            if (song.cover != null)
              CachedNetworkImage(
                imageUrl: song.cover!,
                width: 70,
                height: 70,
                fit: BoxFit.cover,
                httpHeaders: ImageCacheService.headers,
                errorWidget: (context, url, error) => Container(color: Colors.grey, width: 70, height: 70),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    Text(
                      song.name,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (song.artist != null)
                      Text(
                        song.artist!,
                         style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(playerState.isPlaying ? Icons.pause : Icons.play_arrow),
              iconSize: 32,
              onPressed: () {
                ref.read(playerProvider.notifier).togglePlayPause();
              },
            ),
            IconButton(
              icon: const Icon(Icons.playlist_play),
              onPressed: () {
                 showModalBottomSheet(
                     context: context, 
                     isScrollControlled: true,
                     backgroundColor: Colors.transparent,
                     builder: (_) => const PlaylistBottomSheet()
                 );
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
