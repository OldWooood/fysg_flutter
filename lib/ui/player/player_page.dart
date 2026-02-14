import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart'; 
import 'playlist_bottom_sheet.dart';
import '../../providers/player_provider.dart';
import '../../models/song.dart';
import '../../api/image_cache_service.dart';
import '../../l10n/app_localizations.dart';

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({Key? key}) : super(key: key);

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();
  bool _userScrolling = false;
  Timer? _scrollTimer;
  int _lastScrolledIndex = -1;
  int? _currentSongId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  // Simple LRC parser
  List<LyricLine> _parseLyrics(String? lrc) {
    if (lrc == null) return [];
    final List<LyricLine> lyrics = [];
    final RegExp timestampRegex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');
    
    for (final line in lrc.split('\n')) {
      final matches = timestampRegex.allMatches(line);
      if (matches.isEmpty) continue;

      // Extract text by removing all timestamps
      String text = line.replaceAll(timestampRegex, '').trim();
      
      if (text.isEmpty) continue;

      // Add a line for each timestamp found using the cleaned text
      for (final match in matches) {
          final minutes = int.parse(match.group(1)!);
          final seconds = int.parse(match.group(2)!);
          final milliseconds = int.parse(match.group(3)!.padRight(3, '0').substring(0, 3));
          
          lyrics.add(LyricLine(
               offset: Duration(minutes: minutes, seconds: seconds, milliseconds: milliseconds),
               text: text
           ));
      }
    }
    lyrics.sort((a, b) => a.offset.compareTo(b.offset));
    return lyrics;
  }

  void _scrollToCurrentLine(int index) {
      if (_userScrolling || index < 0 || index == _lastScrolledIndex) return;
      try {
          _lastScrolledIndex = index;
          _itemScrollController.scrollTo(
              index: index,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: 0.5 // Center the item
          );
      } catch (e) {
          // ignore scroll errors if list is not ready
      }
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final song = playerState.currentSong;

    // Reset last scrolled index if song changes
    if (song?.id != _currentSongId) {
        _currentSongId = song?.id;
        _lastScrolledIndex = -1;
    }

    final lyrics = _parseLyrics(song?.lyrics);

    if (song == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // Find current lyric index
    int currentIndex = -1;
    for (int i = 0; i < lyrics.length; i++) {
        if (playerState.position >= lyrics[i].offset) {
            currentIndex = i;
        } else {
            break;
        }
    }

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
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
            // Background blur
            Positioned.fill(
                child: song.cover != null 
                ? CachedNetworkImage(
                    imageUrl: song.cover!, 
                    httpHeaders: ImageCacheService.headers,
                    fit: BoxFit.cover, 
                    color: Colors.black.withOpacity(0.7), 
                    colorBlendMode: BlendMode.darken
                  )
                : Container(color: Colors.black),
            ),
            
            Column(
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
                    const SizedBox(height: 40),
                ],
            ),
        ],
      ),
    );
  }

  Widget _buildCoverView(BuildContext context, Song song) {
      return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
               SizedBox(height: kToolbarHeight + 40), // Spacing for AppBar
               Container(
                  height: 300,
                  width: 300,
                  decoration: BoxDecoration(
                     borderRadius: BorderRadius.circular(12),
                     boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 20, offset: Offset(0, 10))],
                  ),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: song.cover != null 
                           ? CachedNetworkImage(
                               imageUrl: song.cover!, 
                               httpHeaders: ImageCacheService.headers,
                               fit: BoxFit.cover
                             )
                           : Container(color: Colors.grey),
                  ),
               ),
               const SizedBox(height: 40),
               Text(
                 song.name,
                 style: Theme.of(context).textTheme.displayMedium?.copyWith(color: Colors.white, fontSize: 32),
                 textAlign: TextAlign.center,
                 maxLines: 2,
                 overflow: TextOverflow.ellipsis,
               ),
               const SizedBox(height: 10),
               Text(
                 song.artist ?? "Unknown Artist",
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white70),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
               ),
          ],
      );
  }

  Widget _buildLyricsView(BuildContext context, List<LyricLine> lyrics, int currentIndex) {
      if (lyrics.isEmpty) {
          return Center(child: Text(AppLocalizations.of(context).noLyrics, style: const TextStyle(color: Colors.white)));
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
              padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + kToolbarHeight + 20, 20, 40),
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

  Widget _buildControls(BuildContext context, dynamic playerState, WidgetRef ref) {
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
                    value: playerState.position.inSeconds.toDouble(),
                    max: playerState.duration.inSeconds.toDouble() > 0 ? playerState.duration.inSeconds.toDouble() : 1.0,
                    onChanged: (value) {
                      ref.read(playerProvider.notifier).seek(Duration(seconds: value.toInt()));
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(playerState.position), style: const TextStyle(color: Colors.white60)),
                      Text(_formatDuration(playerState.duration), style: const TextStyle(color: Colors.white60)),
                    ],
                  ),
                ),

               const SizedBox(height: 10),

               Row(
                 mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                 children: [
                   IconButton(
                     icon: const Icon(Icons.skip_previous, color: Colors.white, size: 40),
                     onPressed: () => ref.read(playerProvider.notifier).previous(),
                   ),
                   Container(
                     decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                     child: IconButton(
                       icon: Icon(playerState.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.black, size: 40),
                       onPressed: () => ref.read(playerProvider.notifier).togglePlayPause(),
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
                           IconButton(
                               icon: Icon(_getModeIcon(playerState.mode), color: Colors.white),
                               onPressed: () => ref.read(playerProvider.notifier).toggleMode(),
                           ),
                           IconButton(
                               icon: const Icon(Icons.download, color: Colors.white),
                               onPressed: () => ref.read(playerProvider.notifier).downloadCurrentSong(),
                           ),
                           IconButton(
                               icon: const Icon(Icons.playlist_play, color: Colors.white),
                               onPressed: () {
                                   showModalBottomSheet(
                                     context: context, 
                                     isScrollControlled: true,
                                     backgroundColor: Colors.transparent,
                                     builder: (_) => const PlaylistBottomSheet()
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
      switch (mode) {
          case PlaybackMode.sequence: return Icons.repeat;
          case PlaybackMode.shuffle: return Icons.shuffle;
          case PlaybackMode.single: return Icons.repeat_one;
      }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds".replaceFirst("00:", "");
  }
}

class LyricLine {
    final Duration offset;
    final String text;
    LyricLine({required this.offset, required this.text});
}
