import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/player_provider.dart';
import '../player/player_page.dart';
import '../player/playlist_bottom_sheet.dart';
import 'song_cover.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerMiniStateProvider);
    final song = playerState.currentSong;

    if (song == null) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = colorScheme.surfaceContainer;
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
      // 左右滑切歌：之前只有点开，单手操作难
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 300) return;
        if (velocity > 0) {
          ref.read(playerProvider.notifier).previous();
        } else {
          ref.read(playerProvider.notifier).next();
        }
      },
      // 上滑展开全屏
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -400) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const PlayerPage(),
              fullscreenDialog: true,
            ),
          );
        }
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _MiniProgressLine(),
            Row(
              children: [
                SongCover(
                  imageUrl: song.cover,
                  width: 70,
                  height: 70,
                  memCacheWidth: 160,
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
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: secondaryColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              button: true,
                              label: MaterialLocalizations.of(
                                context,
                              ).previousPageTooltip,
                              child: IconButton(
                                tooltip: MaterialLocalizations.of(
                                  context,
                                ).previousPageTooltip,
                                icon: Icon(
                                  Icons.skip_previous,
                                  color: foregroundColor,
                                ),
                                // 触摸目标 48dp：之前 compact ~32dp 易误触
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                                onPressed: () {
                                  ref.read(playerProvider.notifier).previous();
                                },
                              ),
                            ),
                          ),
                          Expanded(
                            child: Semantics(
                              button: true,
                              label: playerState.isPlaying
                                  ? AppLocalizations.of(context).pause
                                  : AppLocalizations.of(context).play,
                              child: IconButton(
                                tooltip: playerState.isPlaying
                                    ? AppLocalizations.of(context).pause
                                    : AppLocalizations.of(context).play,
                                icon: Icon(
                                  playerState.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                  color: foregroundColor,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                                onPressed: () {
                                  ref
                                      .read(playerProvider.notifier)
                                      .togglePlayPause();
                                },
                              ),
                            ),
                          ),
                          Expanded(
                            child: Semantics(
                              button: true,
                              label: MaterialLocalizations.of(
                                context,
                              ).nextPageTooltip,
                              child: IconButton(
                                tooltip: MaterialLocalizations.of(
                                  context,
                                ).nextPageTooltip,
                                icon: Icon(
                                  Icons.skip_next,
                                  color: foregroundColor,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                                onPressed: () {
                                  ref.read(playerProvider.notifier).next();
                                },
                              ),
                            ),
                          ),
                          Expanded(
                            child: IconButton(
                              tooltip: AppLocalizations.of(context).playlist,
                              icon: Icon(
                                Icons.playlist_play,
                                color: foregroundColor,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
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
          ],
        ),
      ),
    );
  }
}

/// 顶部细进度指示线：秒级订阅 + RepaintBoundary，避免 10fps 全量重建
class _MiniProgressLine extends ConsumerWidget {
  const _MiniProgressLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positionSeconds = ref.watch(
      playerProvider.select((s) => s.position.inSeconds),
    );
    final durationSeconds = ref.watch(
      playerProvider.select((s) => s.duration.inSeconds),
    );
    final progress = durationSeconds > 0
        ? (positionSeconds / durationSeconds).clamp(0.0, 1.0)
        : 0.0;

    return RepaintBoundary(
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: progress,
          child: Container(
            height: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
