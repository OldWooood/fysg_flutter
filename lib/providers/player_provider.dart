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
  final ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);
  final FysgService _service;
  final RecentlyPlayedService _recentService;

  PlayerNotifier(this._ref, this._service, this._recentService) : super(FysgPlayerState()) {
    _init();
  }

  Future<void> _init() async {
    // Set the playlist as audio source to enable media controls
    try {
      await _audioPlayer.setAudioSource(_playlist);
    } catch (e) {
      print('Error initializing audio player: $e');
    }

    _audioPlayer.playerStateStream.listen((playerState) {
      if (mounted) state = state.copyWith(isPlaying: playerState.playing);
    });

    _audioPlayer.currentIndexStream.listen((index) {
        if (index != null && index < state.queue.length && mounted) {
            final song = state.queue[index];
            if (state.currentIndex != index) {
                state = state.copyWith(currentIndex: index, currentSong: song);
                _recentService.addSong(song);
                _ref.invalidate(recentSongsProvider);
            }
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
      // If we are playing from a queue and this song is in the queue, just seek to it
      if (keepQueue && state.queue.isNotEmpty) {
          final index = state.queue.indexWhere((s) => s.id == song.id);
          if (index != -1) {
              await _audioPlayer.seek(Duration.zero, index: index);
              _audioPlayer.play();
              return;
          }
      }

      // Single song or new queue
      await logQueue([song], 0);
    } catch (e) {
      print("Error playing song (retry $retryCount): $e");
      if (retryCount < 2) {
          await Future.delayed(const Duration(seconds: 1));
          return playSong(song, keepQueue: keepQueue, retryCount: retryCount + 1);
      }
    }
  }

  Future<AudioSource> _createAudioSource(Song song) async {
      final downloadService = DownloadService();
      final localFile = await downloadService.getLocalFile(song.id);
      
      final mediaItem = MediaItem(
          id: song.id.toString(),
          album: song.album ?? "FYSG",
          title: song.name,
          artist: song.artist,
          artUri: song.cover != null ? Uri.parse(song.cover!) : null,
      );

      if (localFile.existsSync()) {
          return AudioSource.file(localFile.path, tag: mediaItem);
      }

      final headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            'Referer': 'https://www.fysg.org/',
      };
      
      return song.url != null 
          ? AudioSource.uri(Uri.parse(song.url!), headers: headers, tag: mediaItem)
          : AudioSource.uri(Uri.parse(""), tag: mediaItem);
  }

  Future<DownloadResult?> downloadCurrentSong() async {
      final song = state.currentSong;
      if (song == null) return null;
      
      try {
          final downloadService = DownloadService();
          if (await downloadService.isDownloaded(song.id)) {
              return DownloadResult.alreadyDownloaded;
          }
          
          // Start download in background
          downloadService.downloadSong(song).then((_) {
              print('Downloaded ${song.name}');
          }).catchError((e) {
              print('Download error: $e');
          });
          
          return DownloadResult.started;
      } catch (e) {
          print('Download error: $e');
          return null;
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
      final List<AudioSource> sources = [];
      for (var song in songs) {
          sources.add(await _createAudioSource(song));
      }
      
      await _playlist.clear();
      await _playlist.addAll(sources);
      await _audioPlayer.setAudioSource(_playlist, initialIndex: index, preload: true);
      
      state = state.copyWith(queue: songs, currentIndex: index, currentSong: songs[index]);
      await _audioPlayer.seek(Duration.zero, index: index);
      _audioPlayer.play();
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
      final newMode = modes[nextIndex];
      state = state.copyWith(mode: newMode);
      
      switch (newMode) {
          case PlaybackMode.sequence:
              _audioPlayer.setLoopMode(LoopMode.all);
              _audioPlayer.setShuffleModeEnabled(false);
              break;
          case PlaybackMode.shuffle:
              _audioPlayer.setLoopMode(LoopMode.all);
              _audioPlayer.setShuffleModeEnabled(true);
              break;
          case PlaybackMode.single:
              _audioPlayer.setLoopMode(LoopMode.one);
              _audioPlayer.setShuffleModeEnabled(false);
              break;
      }
  }

  void next({bool auto = false}) {
      _audioPlayer.seekToNext();
  }
  
  void previous() {
      _audioPlayer.seekToPrevious();
  }
}

enum DownloadResult { started, alreadyDownloaded }
