import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../utils/toast_utils.dart';
import '../common/song_cover.dart';
import 'playlist_bottom_sheet.dart';

/// 歌词行数据
@immutable
class LyricLine {
  final Duration offset;
  final String text;

  const LyricLine({required this.offset, required this.text});
}

/// 歌词解析缓存
/// 使用 Provider 缓存解析结果，避免每次 rebuild 都重新解析
final _lyricsCacheProvider = Provider.family<List<LyricLine>, String?>(
  (ref, lyrics) => _parseLyrics(lyrics),
);

/// 解析 LRC 格式歌词
List<LyricLine> _parseLyrics(String? lrc) {
  if (lrc == null || lrc.isEmpty) return const [];

  final lyrics = <LyricLine>[];
  final timestampRegex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');

  for (final line in lrc.split('\n')) {
    final matches = timestampRegex.allMatches(line);
    if (matches.isEmpty) continue;

    // Extract text by removing all timestamps
    final text = line.replaceAll(timestampRegex, '').trim();
    if (text.isEmpty) continue;

    // Add a line for each timestamp found using the cleaned text
    for (final match in matches) {
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final milliseconds = int.parse(
        match.group(3)!.padRight(3, '0').substring(0, 3),
      );

      lyrics.add(
        LyricLine(
          offset: Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: milliseconds,
          ),
          text: text,
        ),
      );
    }
  }

  lyrics.sort((a, b) => a.offset.compareTo(b.offset));
  return List.unmodifiable(lyrics);
}

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  bool _userScrolling = false;
  Timer? _scrollTimer;
  int _lastScrolledIndex = -1;
  int? _currentSongId;
  int _currentLyricIndex = -1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WakelockPlus.enable();
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 1 && _currentLyricIndex >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToCurrentLine(_currentLyricIndex);
      });
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _scrollTimer?.cancel();
    super.dispose();
  }

  void _scrollToCurrentLine(int index) {
    if (_userScrolling || index < 0 || index == _lastScrolledIndex) return;
    if (!_itemScrollController.isAttached) return;

    _lastScrolledIndex = index;
    _itemScrollController.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.5, // Center the item
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final song = playerState.currentSong;

    // Reset last scrolled index if song changes
    if (song?.id != _currentSongId) {
      _currentSongId = song?.id;
      _lastScrolledIndex = -1;
      if (song != null) {
        ref.read(playerProvider.notifier).ensureSongDetailsLoaded(song.id);
      }
    }

    // 使用 Provider 缓存歌词解析结果
    final lyrics = ref.watch(_lyricsCacheProvider(song?.lyrics));

    if (song == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Find current lyric index
    final currentIndex = _findCurrentLyricIndex(lyrics, playerState.position);
    _currentLyricIndex = currentIndex;

    if (currentIndex != -1 && _tabController.index == 1) {
      // Only auto-scroll if we are looking at lyrics tab
      _scrollToCurrentLine(currentIndex);
    }

    return Scaffold(
      backgroundColor: Colors.black, // Dark immersive mode
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: Colors.white,
            size: 30,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Background Blurred Cover
          Positioned.fill(
            child: song.cover != null
                ? AnimatedSwitcher(
                    duration: const Duration(milliseconds: 1000),
                    child: Stack(
                      key: ValueKey(song.cover),
                      fit: StackFit.expand,
                      children: [
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(
                            sigmaX: 100,
                            sigmaY: 100,
                          ),
                          child: SongCover(
                            imageUrl: song.cover,
                            fit: BoxFit.cover,
                            placeholderIcon: Icons.album,
                            placeholderIconSize: 64,
                          ),
                        ),
                        Container(
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                      ],
                    ),
                  )
                : const ColoredBox(color: Colors.black),
          ),

          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Cover View
                      _buildCoverView(context, song),
                      // Lyrics View
                      _buildLyricsView(context, lyrics, currentIndex),
                    ],
                  ),
                ),

                // Controls (Always visible at bottom)
                _buildControls(context, playerState, ref),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _findCurrentLyricIndex(List<LyricLine> lyrics, Duration position) {
    for (int i = 0; i < lyrics.length; i++) {
      if (position >= lyrics[i].offset) {
        if (i == lyrics.length - 1 || position < lyrics[i + 1].offset) {
          return i;
        }
      }
    }
    return -1;
  }

  Widget _buildCoverView(BuildContext context, Song song) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        // Keep enough room for title/artist so cover never squeezes text out.
        final imageSize = (availableHeight * 0.46).clamp(160.0, 240.0);
        final topSpacing = (availableHeight * 0.08).clamp(8.0, 24.0);
        final middleSpacing = (availableHeight * 0.04).clamp(10.0, 18.0);
        final titleFontSize = (availableHeight * 0.055).clamp(22.0, 30.0);

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: topSpacing),
                  Container(
                    height: imageSize,
                    width: imageSize,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 20,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SongCover(
                        imageUrl: song.cover,
                        fit: BoxFit.cover,
                        placeholderIcon: Icons.album,
                        placeholderIconSize: 56,
                      ),
                    ),
                  ),
                  SizedBox(height: middleSpacing),
                  Text(
                    song.name,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: Colors.white,
                      fontSize: titleFontSize,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    song.artist ?? 'Unknown Artist',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white70,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLyricsView(
    BuildContext context,
    List<LyricLine> lyrics,
    int currentIndex,
  ) {
    if (lyrics.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).noLyrics,
          style: const TextStyle(color: Colors.white),
        ),
      );
    }

    return GestureDetector(
      onTapDown: (_) {
        _userScrolling = true;
        _scrollTimer?.cancel();
      },
      onTapUp: (_) {
        _scrollTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) _userScrolling = false;
        });
      },
      child: ScrollablePositionedList.builder(
        itemScrollController: _itemScrollController,
        itemPositionsListener: _itemPositionsListener,
        itemCount: lyrics.length,
        // Increased top padding to avoid overlap with AppBar/TabBar
        padding: EdgeInsets.fromLTRB(
          20,
          kToolbarHeight + 20,
          20,
          MediaQuery.paddingOf(context).bottom + 40,
        ),
        itemBuilder: (context, index) {
          final isCurrent = index == currentIndex;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                lyrics[index].text,
                style: TextStyle(
                  color: isCurrent ? Colors.white : Colors.white38,
                  fontSize: isCurrent ? 24 : 18,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildControls(
    BuildContext context,
    FysgPlayerState playerState,
    WidgetRef ref,
  ) {
    final maxSeconds = playerState.duration.inSeconds > 0
        ? playerState.duration.inSeconds.toDouble()
        : 1.0;
    final sliderValue = playerState.position.inSeconds.toDouble().clamp(
          0.0,
          maxSeconds,
        );

    return Column(
      children: [
        // TabBar moved here
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            dividerColor: Colors.transparent,
            tabs: [
              Tab(text: AppLocalizations.of(context).songTab),
              Tab(text: AppLocalizations.of(context).lyricsTab),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            trackHeight: 4,
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
          ),
          child: Slider(
            min: 0.0,
            value: sliderValue,
            max: maxSeconds,
            onChanged: (value) {
              ref
                  .read(playerProvider.notifier)
                  .seek(Duration(seconds: value.toInt()));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(playerState.position),
                style: const TextStyle(color: Colors.white60),
              ),
              Text(
                _formatDuration(playerState.duration),
                style: const TextStyle(color: Colors.white60),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(
                Icons.skip_previous,
                color: Colors.white,
                size: 40,
              ),
              onPressed: () => ref.read(playerProvider.notifier).previous(),
            ),
            Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: IconButton(
                icon: Icon(
                  playerState.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.black,
                  size: 40,
                ),
                onPressed: () =>
                    ref.read(playerProvider.notifier).togglePlayPause(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.skip_next, color: Colors.white, size: 40),
              onPressed: () => ref.read(playerProvider.notifier).next(),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Bottom Options (Mode & Playlist)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildOptionButton(
                context,
                icon: _getModeIcon(playerState.mode),
                label: _getModeLabel(playerState.mode, context),
                onPressed: () => ref.read(playerProvider.notifier).toggleMode(),
              ),
              _buildOptionButton(
                context,
                icon: Icons.download,
                label: AppLocalizations.of(context).download,
                onPressed: () async {
                  final result = await ref
                      .read(playerProvider.notifier)
                      .downloadCurrentSong();
                  if (result == null || !context.mounted) return;

                  final message = result == DownloadResult.started
                      ? AppLocalizations.of(context).downloadStarted
                      : AppLocalizations.of(context).alreadyDownloaded;

                  ToastUtils.showToast(context, message);
                },
              ),
              _buildOptionButton(
                context,
                icon: Icons.playlist_play,
                label: AppLocalizations.of(context).playlist,
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const PlaylistBottomSheet(),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _getModeIcon(PlaybackMode mode) {
    return switch (mode) {
      PlaybackMode.sequence => Icons.repeat,
      PlaybackMode.shuffle => Icons.shuffle,
      PlaybackMode.single => Icons.repeat_one,
    };
  }

  String _getModeLabel(PlaybackMode mode, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (mode) {
      PlaybackMode.sequence => l10n.loopOrder,
      PlaybackMode.shuffle => l10n.loopShuffle,
      PlaybackMode.single => l10n.loopSingle,
    };
  }

  Widget _buildOptionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(icon, color: Colors.white),
            onPressed: onPressed,
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    final twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds'
        .replaceFirst('00:', '');
  }
}
