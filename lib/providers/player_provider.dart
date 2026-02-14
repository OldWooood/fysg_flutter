import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';
import '../api/fysg_service.dart';
import '../api/recently_played_service.dart';
import '../api/image_cache_service.dart';
import '../api/download_service.dart';

final fysgServiceProvider = Provider((ref) => FysgService());

final recentlyPlayedServiceProvider = Provider((ref) => RecentlyPlayedService());

final recentSongsProvider = FutureProvider<List<Song>>((ref) async {
  return ref.watch(recentlyPlayedServiceProvider).getRecentSongs();
});

final playerProvider = StateNotifierProvider<PlayerNotifier, FysgPlayerState>((ref) {
  return PlayerNotifier(
      ref,
      ref.watch(fysgServiceProvider), 
      ref.watch(recentlyPlayedServiceProvider)
  );
});

enum PlaybackMode { sequence, shuffle, single }

class FysgPlayerState {
  final bool isPlaying;
  final Song? currentSong;
  final Duration position;
  final Duration duration;
  final List<Song> queue;
  final int currentIndex;
  final PlaybackMode mode;

  FysgPlayerState({
    this.isPlaying = false,
    this.currentSong,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.queue = const [],
    this.currentIndex = -1,
    this.mode = PlaybackMode.sequence,
  });

  FysgPlayerState copyWith({
    bool? isPlaying,
    Song? currentSong,
    Duration? position,
    Duration? duration,
    List<Song>? queue,
    int? currentIndex,
    PlaybackMode? mode,
  }) {
    return FysgPlayerState(
      isPlaying: isPlaying ?? this.isPlaying,
      currentSong: currentSong ?? this.currentSong,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      mode: mode ?? this.mode,
    );
  }
}

class PlayerNotifier extends StateNotifier<FysgPlayerState> {
  final Ref _ref;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FysgService _service;
  final RecentlyPlayedService _recentService;

  PlayerNotifier(this._ref, this._service, this._recentService) : super(FysgPlayerState()) {
    _init();
  }

  void _init() {
    _audioPlayer.playerStateStream.listen((playerState) {
      state = state.copyWith(isPlaying: playerState.playing);
      if (playerState.processingState == ProcessingState.completed) {
          next(auto: true);
      }
    });

    _audioPlayer.positionStream.listen((position) {
      if (mounted) state = state.copyWith(position: position);
    });

    _audioPlayer.durationStream.listen((duration) {
      if (mounted) state = state.copyWith(duration: duration ?? Duration.zero);
    });

    _audioPlayer.playbackEventStream.listen((event) {
        // Log playback events for debugging stalls
    }, onError: (Object e, StackTrace st) {
        print('Playback error: $e');
    });
  }

  Future<void> playSong(Song song, {bool keepQueue = false, int retryCount = 0}) async {
    try {
      // Check if downloaded
      final downloadService = DownloadService();
      final localFile = await downloadService.getLocalFile(song.id);
      
      Song fullSong = song;
      if (!localFile.existsSync()) {
          // Fetch full details if not downloaded (to get URL/Lyrics)
          fullSong = await _service.getSongDetails(song.id);
      }
      
      if (fullSong.url == null && !localFile.existsSync()) return;

      await _recentService.addSong(fullSong);
      _ref.invalidate(recentSongsProvider);

      state = state.copyWith(currentSong: fullSong);

      final headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            'Referer': 'https://www.fysg.org/',
            'Origin': 'https://www.fysg.org',
            'Sec-Fetch-Dest': 'audio',
            'Sec-Fetch-Mode': 'no-cors',
            'Sec-Fetch-Site': 'cross-site',
      };

      AudioSource source;
      if (localFile.existsSync()) {
          source = AudioSource.file(
            localFile.path,
            tag: MediaItem(
              id: fullSong.id.toString(),
              album: fullSong.album ?? "FYSG",
              title: fullSong.name,
              artist: fullSong.artist,
            ),
          );
      } else {
          // Use LockCachingAudioSource to mitigate codec stalls and buffer underruns
          source = LockCachingAudioSource(
            Uri.parse(fullSong.url!),
            headers: headers,
            tag: MediaItem(
              id: fullSong.id.toString(),
              album: fullSong.album ?? "FYSG",
              title: fullSong.name,
              artist: fullSong.artist,
            ),
          );
      }

      await _audioPlayer.setAudioSource(source);
      state = state.copyWith(isPlaying: true);
      _audioPlayer.play();

      if (fullSong.cover != null) {
          _updateArtworkInBackground(fullSong);
      }
    } catch (e) {
      print("Error playing song (retry $retryCount): $e");
      if (retryCount < 2) {
          await Future.delayed(const Duration(seconds: 1));
          return playSong(song, keepQueue: keepQueue, retryCount: retryCount + 1);
      }
    }
  }

  Future<void> downloadCurrentSong() async {
      final song = state.currentSong;
      if (song == null) return;
      
      try {
          final downloadService = DownloadService();
          await downloadService.downloadSong(song);
          // Force state update if needed, but for now just log
          print('Downloaded ${song.name}');
      } catch (e) {
          print('Download error: $e');
      }
  }

  Future<void> _updateArtworkInBackground(Song song) async {
       try {
          await ImageCacheService().getCachedImagePath(song.cover!);
       } catch (e) {
           print("Error loading art: $e");
       }
  }

  Future<void> logQueue(List<Song> songs, int index) async {
      state = state.copyWith(queue: songs, currentIndex: index);
      playSong(songs[index], keepQueue: true);
  }

  void togglePlayPause() {
    if (_audioPlayer.playing) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play();
    }
  }

  void seek(Duration position) {
    _audioPlayer.seek(position);
  }

  void toggleMode() {
      final modes = PlaybackMode.values;
      final nextIndex = (state.mode.index + 1) % modes.length;
      state = state.copyWith(mode: modes[nextIndex]);
  }

  void next({bool auto = false}) {
      if (state.queue.isEmpty) return;

      int nextIndex = state.currentIndex;

      if (state.mode == PlaybackMode.single && auto) {
          // Loop single song
          seek(Duration.zero);
          _audioPlayer.play();
          return;
      } else if (state.mode == PlaybackMode.shuffle) {
          // Random index
          if (state.queue.length > 1) {
              // Simple random for now, ideally we avoid recent history
              nextIndex = (DateTime.now().millisecond) % state.queue.length;
              if (nextIndex == state.currentIndex) nextIndex = (nextIndex + 1) % state.queue.length;
          }
      } else {
          // Sequence (Loop List)
          nextIndex = (state.currentIndex + 1) % state.queue.length;
      }

      state = state.copyWith(currentIndex: nextIndex);
      playSong(state.queue[nextIndex], keepQueue: true);
  }

  void previous() {
       if (state.queue.isEmpty) return;
       
       int prevIndex = state.currentIndex;
       if (state.mode == PlaybackMode.shuffle) {
           // For shuffle, prev usually goes to history, but for simplicity here strictly random 
           // or just go back to strict previous in list? standard behavior varies.
           // Let's just go to previous in list for now to allow navigating the list.
           if (prevIndex > 0) prevIndex--;
           else prevIndex = state.queue.length - 1;
       } else {
           if (prevIndex > 0) prevIndex--;
           else prevIndex = state.queue.length - 1;
       }
       
       state = state.copyWith(currentIndex: prevIndex);
       playSong(state.queue[prevIndex], keepQueue: true);
  }
}
