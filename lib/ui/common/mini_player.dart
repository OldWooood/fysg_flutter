import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/player_provider.dart';
import '../player/player_page.dart';
import '../player/playlist_bottom_sheet.dart';
import 'song_cover.dart';

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerMiniStateProvider);
    final song = playerState.currentSong;

    if (song == null) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = colorScheme.surface;
    final foregroundColor = colorScheme.onSurface;
    final secondaryColor = foregroundColor.withValues(alpha: 0.7);

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
          color: backgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 16,
              spreadRadius: 1,
              offset: const Offset(0, -4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 28,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SongCover(
              imageUrl: song.cover,
              width: 70,
              height: 70,
              fit: BoxFit.cover,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.name,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: foregroundColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (song.artist != null)
                    Text(
                      song.artist!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: secondaryColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: IconButton(
                          icon: Icon(
                            Icons.skip_previous,
                            color: foregroundColor,
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            ref.read(playerProvider.notifier).previous();
                          },
                        ),
                      ),
                      Expanded(
                        child: IconButton(
                          icon: Icon(
                            playerState.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: foregroundColor,
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            ref.read(playerProvider.notifier).togglePlayPause();
                          },
                        ),
                      ),
                      Expanded(
                        child: IconButton(
                          icon: Icon(Icons.skip_next, color: foregroundColor),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            ref.read(playerProvider.notifier).next();
                          },
                        ),
                      ),
                      Expanded(
                        child: IconButton(
                          icon: Icon(
                            Icons.playlist_play,
                            color: foregroundColor,
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const PlaylistBottomSheet(),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
