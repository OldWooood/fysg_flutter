import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../api/image_cache_service.dart';
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
  static final Map<String, Color> _dominantColorCache = {};
  String? _coverUrl;
  Color? _dominantColor;

  Future<void> _updateDominantColor(String? coverUrl) async {
    if (coverUrl == null || coverUrl.isEmpty) {
      if (!mounted) return;
      setState(() {
        _coverUrl = null;
        _dominantColor = null;
      });
      return;
    }
    if (_coverUrl == coverUrl) return;

    _coverUrl = coverUrl;
    final cached = _dominantColorCache[coverUrl];
    if (cached != null) {
      if (!mounted) return;
      setState(() => _dominantColor = cached);
      return;
    }

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(
          coverUrl,
          headers: ImageCacheService.headers,
        ),
        size: const Size(64, 64),
        maximumColorCount: 12,
      );
      final color = palette.dominantColor?.color;
      if (color != null) {
        _dominantColorCache[coverUrl] = color;
      }
      if (!mounted || _coverUrl != coverUrl) return;
      setState(() => _dominantColor = color);
    } catch (_) {
      if (!mounted || _coverUrl != coverUrl) return;
      setState(() => _dominantColor = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerMiniStateProvider);
    final song = playerState.currentSong;

    if (song == null) return const SizedBox.shrink();
    _updateDominantColor(song.cover);

    final baseColor =
        _dominantColor ?? Theme.of(context).scaffoldBackgroundColor;
    final backgroundColor =
        Color.lerp(baseColor, Colors.black, 0.18) ?? baseColor;

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
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (song.artist != null)
                    Text(
                      song.artist!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: IconButton(
                          icon: const Icon(
                            Icons.skip_previous,
                            color: Colors.white,
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
                            color: Colors.white,
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            ref.read(playerProvider.notifier).togglePlayPause();
                          },
                        ),
                      ),
                      Expanded(
                        child: IconButton(
                          icon: const Icon(
                            Icons.skip_next,
                            color: Colors.white,
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            ref.read(playerProvider.notifier).next();
                          },
                        ),
                      ),
                      Expanded(
                        child: IconButton(
                          icon: const Icon(
                            Icons.playlist_play,
                            color: Colors.white,
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
