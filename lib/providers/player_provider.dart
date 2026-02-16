import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import '../api/fysg_service.dart';
import '../api/recently_played_service.dart';
import '../api/download_service.dart';
import '../audio/app_audio_handler.dart';

final fysgServiceProvider = Provider((ref) => FysgService());

final recentlyPlayedServiceProvider = Provider(
  (ref) => RecentlyPlayedService(),
);

final recentSongsProvider = FutureProvider<List<Song>>((ref) async {
  return ref.watch(recentlyPlayedServiceProvider).getRecentSongs();
});

final playerMiniStateProvider = Provider<({Song? currentSong, bool isPlaying})>(
  (ref) {
    return ref.watch(
      playerProvider.select(
        (state) => (currentSong: state.currentSong, isPlaying: state.isPlaying),
      ),
    );
  },
);

final playerQueueStateProvider =
    Provider<({List<Song> queue, int currentIndex, PlaybackMode mode})>((ref) {
      return ref.watch(
        playerProvider.select(
          (state) => (
            queue: state.queue,
            currentIndex: state.currentIndex,
            mode: state.mode,
          ),
        ),
      );
    });

final playerProvider = StateNotifierProvider<PlayerNotifier, FysgPlayerState>((
  ref,
) {
  return PlayerNotifier(
    ref,
    ref.watch(fysgServiceProvider),
    ref.watch(recentlyPlayedServiceProvider),
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
  static const int _maxSongLoadRetries = 2;
  final Ref _ref;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(
    children: [],
  );
  final FysgService _service;
  final DownloadService _downloadService = DownloadService();
  final RecentlyPlayedService _recentService;
  final Map<int, Song> _songDetailsCache = {};
  final Set<int> _songDetailsLoading = {};
  int _queueBuildToken = 0;
  bool _suppressIndexSync = false;
  ProcessingState _processingState = ProcessingState.idle;
  final Map<int, int> _songLoadRetryCount = {};
  int? _lastPrefetchSongId;
  bool _isPrefetching = false;
  bool _prefetchCacheLoaded = false;
  Set<int> _prefetchCachedIds = {};

  PlayerNotifier(this._ref, this._service, this._recentService)
    : super(FysgPlayerState()) {
    _init();
  }

  Future<void> _init() async {
    // Set the playlist as audio source to enable media controls
    try {
      await _audioPlayer.setAudioSource(_playlist);
      // Keep initial behavior aligned with default sequence mode.
      await _audioPlayer.setLoopMode(LoopMode.all);
      await _audioPlayer.setShuffleModeEnabled(false);
    } catch (e) {
      print('Error initializing audio player: $e');
    }

    _audioPlayer.playerStateStream.listen((playerState) {
      _processingState = playerState.processingState;
      _syncBackgroundPlayback();
      if (!mounted || state.isPlaying == playerState.playing) return;
      state = state.copyWith(isPlaying: playerState.playing);
    });

    _audioPlayer.currentIndexStream.listen((index) {
      if (_suppressIndexSync) return;
      if (index != null && index < state.queue.length && mounted) {
        _songLoadRetryCount[state.queue[index].id] = 0;
        _lastPrefetchSongId = null;
        final song = state.queue[index];
        if (state.currentIndex != index) {
          state = state.copyWith(currentIndex: index, currentSong: song);
          _syncBackgroundNowPlaying(song);
          _recentService.addSong(song);
          _ref.invalidate(recentSongsProvider);
        }
      }
    });

    _audioPlayer.positionStream.listen((position) {
      if (!mounted || state.position == position) return;
      state = state.copyWith(position: position);
      _syncBackgroundPlayback();
      _maybePrefetchNext(position);
    });

    _audioPlayer.durationStream.listen((duration) {
      final nextDuration = duration ?? Duration.zero;
      if (!mounted || state.duration == nextDuration) return;
      state = state.copyWith(duration: nextDuration);
      _syncBackgroundPlayback();
    });

    _audioPlayer.playbackEventStream.listen(
      (event) {
        // Log playback events for debugging stalls
      },
      onError: (Object e, StackTrace st) {
        print('Playback error: $e');
        _handleSongLoadFailure('playback_event_error');
      },
    );
  }

  Future<void> playSong(
    Song song, {
    bool keepQueue = false,
    int retryCount = 0,
  }) async {
    try {
      await _loadPrefetchCacheIfNeeded();
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
      if (retryCount < _maxSongLoadRetries) {
        await Future.delayed(const Duration(seconds: 1));
        return playSong(song, keepQueue: keepQueue, retryCount: retryCount + 1);
      }
      _handleSongLoadFailure('play_song_failed');
    }
  }

  Future<void> _handleSongLoadFailure(String reason) async {
    final currentSong = state.currentSong;
    if (currentSong == null) return;

    final retries = (_songLoadRetryCount[currentSong.id] ?? 0) + 1;
    _songLoadRetryCount[currentSong.id] = retries;

    if (retries <= _maxSongLoadRetries) {
      print(
        'Retry loading song ${currentSong.id} ($retries/$_maxSongLoadRetries), reason: $reason',
      );
      try {
        await _audioPlayer.seek(Duration.zero);
        await _audioPlayer.play();
        return;
      } catch (e) {
        print('Retry failed for song ${currentSong.id}: $e');
      }
    }

    print(
      'Skip song ${currentSong.id} after retries exhausted, reason: $reason',
    );
    _songLoadRetryCount[currentSong.id] = 0;
    next(auto: true);
  }

  void _maybePrefetchNext(Duration position) {
    final durationMs = state.duration.inMilliseconds;
    if (durationMs <= 0) return;
    if (position.inMilliseconds < durationMs ~/ 2) return;
    if (state.queue.length < 2) return;
    if (state.currentIndex < 0 || state.currentIndex >= state.queue.length) {
      return;
    }

    final nextIndex = _resolveNextIndexForPrefetch();
    if (nextIndex == null) return;
    if (nextIndex < 0 || nextIndex >= state.queue.length) return;

    final nextSong = state.queue[nextIndex];
    if (_lastPrefetchSongId == nextSong.id) return;

    _lastPrefetchSongId = nextSong.id;
    _maybeUsePrefetched(nextSong).then((used) {
      if (!used) {
        _prefetchSong(nextSong);
      }
    });
  }

  int? _resolveNextIndexForPrefetch() {
    if (state.queue.isEmpty || state.currentIndex < 0) return null;
    switch (state.mode) {
      case PlaybackMode.single:
        return null;
      case PlaybackMode.sequence:
        return (state.currentIndex + 1) % state.queue.length;
      case PlaybackMode.shuffle:
        return _audioPlayer.nextIndex;
    }
  }

  Future<void> _prefetchSong(Song song) async {
    if (_isPrefetching) return;
    _isPrefetching = true;
    try {
      if (await _downloadService.isDownloaded(song.id)) return;
      await _downloadService.prefetchSong(song);
      _prefetchCachedIds.add(song.id);
    } catch (e) {
      print('Prefetch failed for song ${song.id}: $e');
    } finally {
      _isPrefetching = false;
    }
  }

  Future<void> _loadPrefetchCacheIfNeeded() async {
    if (_prefetchCacheLoaded) return;
    _prefetchCachedIds = await _downloadService.listPrefetchedSongIds();
    _prefetchCacheLoaded = true;
  }

  Future<bool> _maybeUsePrefetched(Song song) async {
    if (!_prefetchCacheLoaded) {
      await _loadPrefetchCacheIfNeeded();
    }
    if (!_prefetchCachedIds.contains(song.id)) return false;
    if (!await _downloadService.isPrefetched(song.id)) {
      _prefetchCachedIds.remove(song.id);
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<AudioSource> _createAudioSource(Song song) async {
    final prefetched = await _downloadService.getPrefetchFile(song.id);
    if (prefetched.existsSync()) {
      _prefetchCachedIds.add(song.id);
      return AudioSource.file(prefetched.path);
    }

    final localFile = await _downloadService.getLocalFile(song.id);

    if (localFile.existsSync()) {
      return AudioSource.file(localFile.path);
    }

    final url = song.url;
    if (url == null || url.isEmpty) {
      throw Exception('Missing audio url for song ${song.id}');
    }

    final headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      'Referer': 'https://www.fysg.org/',
    };

    return AudioSource.uri(Uri.parse(url), headers: headers);
  }

  Future<DownloadResult?> downloadCurrentSong() async {
    final song = state.currentSong;
    if (song == null) return null;

    try {
      if (await _downloadService.isDownloaded(song.id)) {
        return DownloadResult.alreadyDownloaded;
      }

      // Start download in background
      _downloadService
          .downloadSong(song)
          .then((_) {
            print('Downloaded ${song.name}');
          })
          .catchError((e) {
            print('Download error: $e');
          });

      return DownloadResult.started;
    } catch (e) {
      print('Download error: $e');
      return null;
    }
  }

  Future<void> logQueue(List<Song> songs, int index) async {
    if (songs.isEmpty) return;
    if (index < 0 || index >= songs.length) return;

    final buildToken = ++_queueBuildToken;
    final preferred = await _buildPlayableEntry(songs[index]);
    var firstPlayable = preferred;
    var chosenOriginalIndex = index;
    if (firstPlayable == null) {
      for (var offset = 0; offset < songs.length; offset++) {
        final originalIndex = (index + offset) % songs.length;
        final song = songs[originalIndex];
        firstPlayable = await _buildPlayableEntry(song);
        if (firstPlayable != null) {
          chosenOriginalIndex = originalIndex;
          break;
        }
      }
    }

    if (firstPlayable == null) {
      print('No playable songs in queue');
      return;
    }

    final displayQueue = List<Song>.from(songs);
    final safeDisplayIndex =
        (chosenOriginalIndex >= 0 && chosenOriginalIndex < displayQueue.length)
        ? chosenOriginalIndex
        : index;

    // Show full list immediately; keep index stream from remapping to stale index 0.
    state = state.copyWith(
      queue: displayQueue,
      currentIndex: safeDisplayIndex,
      currentSong: displayQueue[safeDisplayIndex],
    );
    _syncBackgroundNowPlaying(displayQueue[safeDisplayIndex]);
    _suppressIndexSync = true;

    await _playlist.clear();
    await _playlist.add(firstPlayable.source);
    await _audioPlayer.setAudioSource(
      _playlist,
      initialIndex: 0,
      preload: true,
    );

    await _audioPlayer.seek(Duration.zero, index: 0);
    _audioPlayer.play();

    _expandQueueInBackground(
      songs: songs,
      currentSongSnapshot: firstPlayable.song,
      buildToken: buildToken,
    );
  }

  Future<void> _expandQueueInBackground({
    required List<Song> songs,
    required Song currentSongSnapshot,
    required int buildToken,
  }) async {
    final playableSongs = <Song>[];
    final sources = <AudioSource>[];

    for (final song in songs) {
      final entry = await _buildPlayableEntry(song);
      if (entry == null) continue;
      playableSongs.add(entry.song);
      sources.add(entry.source);
    }

    if (!mounted || buildToken != _queueBuildToken || playableSongs.isEmpty) {
      if (buildToken == _queueBuildToken) {
        _suppressIndexSync = false;
      }
      return;
    }

    var currentIndex = playableSongs.indexWhere(
      (song) => _isSameSong(song, currentSongSnapshot),
    );
    if (currentIndex < 0) {
      currentIndex = playableSongs.indexWhere(
        (song) => song.id == currentSongSnapshot.id,
      );
    }
    if (currentIndex < 0) return;

    final resumePosition = _audioPlayer.position;
    final shouldResume = _audioPlayer.playing;

    await _playlist.clear();
    await _playlist.addAll(sources);
    await _audioPlayer.setAudioSource(
      _playlist,
      initialIndex: currentIndex,
      initialPosition: resumePosition,
      preload: true,
    );

    if (!mounted || buildToken != _queueBuildToken) return;

    state = state.copyWith(
      queue: playableSongs,
      currentIndex: currentIndex,
      currentSong: playableSongs[currentIndex],
    );
    _syncBackgroundNowPlaying(playableSongs[currentIndex]);
    _suppressIndexSync = false;

    if (shouldResume) {
      _audioPlayer.play();
    }
  }

  Future<({Song song, AudioSource source})?> _buildPlayableEntry(
    Song song,
  ) async {
    Song resolvedSong = song;
    try {
      final source = await _createAudioSource(resolvedSong);
      return (song: resolvedSong, source: source);
    } catch (_) {
      if (resolvedSong.id == 0) return null;
      try {
        final details = await _service.getSongDetails(resolvedSong.id);
        _songDetailsCache[resolvedSong.id] = details;
        resolvedSong = _mergeSong(resolvedSong, details);
        final source = await _createAudioSource(resolvedSong);
        return (song: resolvedSong, source: source);
      } catch (e) {
        print('Skip unplayable song ${song.id}: $e');
        return null;
      }
    }
  }

  Future<void> ensureCurrentSongDetailsLoaded() async {
    final song = state.currentSong;
    if (song == null) return;
    await ensureSongDetailsLoaded(song.id);
  }

  Future<void> ensureSongDetailsLoaded(int songId) async {
    Song? baseSong;
    if (state.currentSong?.id == songId) {
      baseSong = state.currentSong;
    } else {
      for (final song in state.queue) {
        if (song.id == songId) {
          baseSong = song;
          break;
        }
      }
    }
    if (baseSong == null) return;
    if ((baseSong.lyrics?.isNotEmpty ?? false)) return;

    final cached = _songDetailsCache[songId];
    if (cached != null) {
      _mergeSongDetailsIntoState(cached);
      return;
    }

    if (_songDetailsLoading.contains(songId)) return;
    _songDetailsLoading.add(songId);
    try {
      final details = await _service.getSongDetails(songId);
      _songDetailsCache[songId] = details;
      _mergeSongDetailsIntoState(details);
    } catch (e) {
      print('Failed to load song details for $songId: $e');
    } finally {
      _songDetailsLoading.remove(songId);
    }
  }

  void _mergeSongDetailsIntoState(Song detailedSong) {
    Song? mergedCurrentSong = state.currentSong;
    var currentSongChanged = false;
    if (mergedCurrentSong?.id == detailedSong.id) {
      final merged = _mergeSong(mergedCurrentSong!, detailedSong);
      if (!_isSameSong(mergedCurrentSong, merged)) {
        mergedCurrentSong = merged;
        currentSongChanged = true;
      }
    }

    var queueChanged = false;
    final mergedQueue = <Song>[];
    for (final song in state.queue) {
      if (song.id != detailedSong.id) {
        mergedQueue.add(song);
        continue;
      }
      final merged = _mergeSong(song, detailedSong);
      mergedQueue.add(merged);
      if (!_isSameSong(song, merged)) {
        queueChanged = true;
      }
    }

    if (!currentSongChanged && !queueChanged) return;
    state = state.copyWith(
      currentSong: mergedCurrentSong,
      queue: queueChanged ? mergedQueue : state.queue,
    );
    _syncBackgroundNowPlaying(state.currentSong);
  }

  void _syncBackgroundNowPlaying(Song? song) {
    final handler = AppAudioService.handler;
    if (handler == null) return;
    handler.setNowPlaying(song);
    _syncBackgroundPlayback();
  }

  void _syncBackgroundPlayback() {
    final handler = AppAudioService.handler;
    if (handler == null) return;
    handler.setPlayback(
      isPlaying: _audioPlayer.playing,
      position: _audioPlayer.position,
      bufferedPosition: _audioPlayer.bufferedPosition,
      speed: _audioPlayer.speed,
      processingState: _processingState,
    );
  }

  Song _mergeSong(Song base, Song details) {
    final detailsLyrics = details.lyrics;
    return Song(
      id: base.id,
      name: details.name.isNotEmpty ? details.name : base.name,
      artist: details.artist ?? base.artist,
      album: details.album ?? base.album,
      cover: details.cover ?? base.cover,
      url: details.url ?? base.url,
      lyrics: (detailsLyrics != null && detailsLyrics.isNotEmpty)
          ? detailsLyrics
          : base.lyrics,
    );
  }

  bool _isSameSong(Song a, Song b) {
    return a.id == b.id &&
        a.name == b.name &&
        a.artist == b.artist &&
        a.album == b.album &&
        a.cover == b.cover &&
        a.url == b.url &&
        a.lyrics == b.lyrics;
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
    final currentSong = state.currentSong;
    if (currentSong != null) {
      _songLoadRetryCount[currentSong.id] = 0;
    }
    if (auto && state.mode == PlaybackMode.single && state.queue.length > 1) {
      final nextIndex = (state.currentIndex + 1) % state.queue.length;
      _audioPlayer.seek(Duration.zero, index: nextIndex);
      _audioPlayer.play();
      return;
    }
    _audioPlayer.seekToNext();
  }

  void previous() {
    _audioPlayer.seekToPrevious();
  }
}

enum DownloadResult { started, alreadyDownloaded }
