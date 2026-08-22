import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../api/download_service.dart';
import '../api/fysg_service.dart';
import '../api/recently_played_service.dart'
    show
        recentlyPlayedServiceProvider,
        recentSongsProvider,
        RecentlyPlayedService;
import '../audio/app_audio_handler.dart';
import '../models/song.dart';
import '../utils/constants.dart';
import 'shared_preferences_provider.dart';

final fysgServiceProvider = Provider((ref) {
  final service = FysgService();
  ref.onDispose(service.dispose);
  return service;
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
    ref.watch(downloadServiceProvider),
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
  final double speed;

  const FysgPlayerState({
    this.isPlaying = false,
    this.currentSong,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.queue = const [],
    this.currentIndex = -1,
    this.mode = PlaybackMode.sequence,
    this.speed = 1.0,
  });

  FysgPlayerState copyWith({
    bool? isPlaying,
    Song? currentSong,
    Duration? position,
    Duration? duration,
    List<Song>? queue,
    int? currentIndex,
    PlaybackMode? mode,
    double? speed,
  }) {
    return FysgPlayerState(
      isPlaying: isPlaying ?? this.isPlaying,
      currentSong: currentSong ?? this.currentSong,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      mode: mode ?? this.mode,
      speed: speed ?? this.speed,
    );
  }
}

class PlayerNotifier extends StateNotifier<FysgPlayerState>
    implements AppAudioHandlerDelegate {
  final Ref _ref;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FysgService _service;
  final DownloadService _downloadService;
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
  bool _queueStateRestored = false;
  int? _lastHistorySongId;
  DateTime _lastPositionPersist = DateTime.now();

  /// 冷启动恢复队列时待使用的续播位置，
  /// 在队列展开完成、真正加载音源时一次性消费
  Duration _pendingRestorePosition = Duration.zero;

  /// 播放中定期持久化进度的间隔，避免频繁写 SharedPreferences
  static const _positionPersistInterval = Duration(seconds: 5);

  // Stream 订阅管理，防止内存泄漏
  final List<StreamSubscription> _subscriptions = [];
  bool _isDisposed = false;

  PlayerNotifier(
    this._ref,
    this._service,
    this._downloadService,
    this._recentService,
  ) : super(const FysgPlayerState()) {
    _init();
  }

  bool get _mounted => !_isDisposed;

  Future<void> _init() async {
    // Set the playlist as audio source to enable media controls
    try {
      await _audioPlayer.setAudioSources(const []);
      // Keep initial behavior aligned with default sequence mode.
      await _audioPlayer.setLoopMode(LoopMode.all);
      await _audioPlayer.setShuffleModeEnabled(false);
    } catch (e) {
      debugPrint('Error initializing audio player: $e');
    }

    // 接入通知栏/锁屏/耳机的播放控制指令
    AppAudioService.handler?.attachDelegate(this);

    // 使用订阅列表管理所有 Stream 订阅
    _subscriptions.add(
      _audioPlayer.playerStateStream.listen(
        (playerState) {
          _processingState = playerState.processingState;
          _syncBackgroundPlayback();
          if (!_mounted || state.isPlaying == playerState.playing) return;
          state = state.copyWith(isPlaying: playerState.playing);
          if (playerState.playing) {
            _logHistoryIfNeeded();
          } else {
            // 暂停时持久化位置，保证下次冷启动可续播
            _persistPlaybackState(includePosition: true);
          }
        },
        onError: (Object e, StackTrace st) {
          debugPrint('PlayerStateStream error: $e');
        },
      ),
    );

    _subscriptions.add(
      _audioPlayer.currentIndexStream.listen(
        (index) {
          if (_suppressIndexSync) return;
          if (index != null && index < state.queue.length && _mounted) {
            _songLoadRetryCount[state.queue[index].id] = 0;
            _lastPrefetchSongId = null;
            final song = state.queue[index];
            if (state.currentIndex != index) {
              state = state.copyWith(currentIndex: index, currentSong: song);
              _persistPlaybackState();
              _syncBackgroundNowPlaying(song);
              _logHistoryIfNeeded();
            }
          }
        },
        onError: (Object e, StackTrace st) {
          debugPrint('CurrentIndexStream error: $e');
        },
      ),
    );

    _subscriptions.add(
      _audioPlayer.positionStream.listen(
        (position) {
          if (!_mounted || state.position == position) return;
          state = state.copyWith(position: position);
          _syncBackgroundPlayback();
          _maybePersistPosition();
          _maybePrefetchNext(position);
        },
        onError: (Object e, StackTrace st) {
          debugPrint('PositionStream error: $e');
        },
      ),
    );

    _subscriptions.add(
      _audioPlayer.speedStream.listen(
        (speed) {
          if (!_mounted || state.speed == speed) return;
          state = state.copyWith(speed: speed);
        },
        onError: (Object e, StackTrace st) {
          debugPrint('SpeedStream error: $e');
        },
      ),
    );

    _subscriptions.add(
      _audioPlayer.durationStream.listen(
        (duration) {
          final nextDuration = duration ?? Duration.zero;
          if (!_mounted || state.duration == nextDuration) return;
          state = state.copyWith(duration: nextDuration);
          _syncBackgroundPlayback();
        },
        onError: (Object e, StackTrace st) {
          debugPrint('DurationStream error: $e');
        },
      ),
    );

    _subscriptions.add(
      _audioPlayer.playbackEventStream.listen(
        (event) {
          // Log playback events for debugging stalls
        },
        onError: (Object e, StackTrace st) {
          debugPrint('Playback error: $e');
          _handleSongLoadFailure('playback_event_error');
        },
      ),
    );

    await _restoreQueueState();
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
      debugPrint("Error playing song (retry $retryCount): $e");
      if (retryCount < AppConstants.maxSongLoadRetries) {
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

    if (retries <= AppConstants.maxSongLoadRetries) {
      debugPrint(
        'Retry loading song ${currentSong.id} ($retries/${AppConstants.maxSongLoadRetries}), reason: $reason',
      );
      try {
        await _audioPlayer.seek(Duration.zero);
        await _audioPlayer.play();
        return;
      } catch (e) {
        debugPrint('Retry failed for song ${currentSong.id}: $e');
      }
    }

    debugPrint(
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
      debugPrint('Prefetch failed for song ${song.id}: $e');
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
    _isDisposed = true;
    // 取消所有 Stream 订阅
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
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

    return AudioSource.uri(
      Uri.parse(url),
      headers: AppConstants.defaultHeaders,
    );
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
            debugPrint('Downloaded ${song.name}');
            // 下载完成后刷新"已下载"列表
            if (_mounted) _ref.invalidate(downloadedSongsProvider);
          })
          .catchError((e) {
            debugPrint('Download error: $e');
          });

      return DownloadResult.started;
    } catch (e) {
      debugPrint('Download error: $e');
      return null;
    }
  }

  Future<void> logQueue(List<Song> songs, int index) async {
    if (songs.isEmpty) return;
    if (index < 0 || index >= songs.length) return;

    final buildToken = ++_queueBuildToken;
    final preferred = await _buildPlayableEntry(songs[index]);
    if (!_mounted || buildToken != _queueBuildToken) return;
    var firstPlayable = preferred;
    var chosenOriginalIndex = index;
    if (firstPlayable == null) {
      for (var offset = 0; offset < songs.length; offset++) {
        final originalIndex = (index + offset) % songs.length;
        final song = songs[originalIndex];
        firstPlayable = await _buildPlayableEntry(song);
        if (!_mounted || buildToken != _queueBuildToken) return;
        if (firstPlayable != null) {
          chosenOriginalIndex = originalIndex;
          break;
        }
      }
    }

    if (firstPlayable == null) {
      debugPrint('No playable songs in queue');
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
    _persistQueueCache();
    _persistPlaybackState();
    _syncBackgroundNowPlaying(displayQueue[safeDisplayIndex]);
    _suppressIndexSync = true;

    await _audioPlayer.setAudioSources(
      [firstPlayable.source],
      initialIndex: 0,
      preload: true,
    );

    if (!_mounted || buildToken != _queueBuildToken) return;
    await _audioPlayer.seek(Duration.zero, index: 0);
    _audioPlayer.play();

    _expandQueueInBackground(
      songs: songs,
      currentSongSnapshot: firstPlayable.song,
      buildToken: buildToken,
    );
  }

  void _logHistoryIfNeeded() {
    final song = state.currentSong;
    if (song == null) return;
    if (_lastHistorySongId == song.id) return;
    _lastHistorySongId = song.id;
    _recentService.addSong(song);
    _ref.invalidate(recentSongsProvider);
  }

  Future<void> restoreCachedQueue() async {
    await _restoreQueueState();
  }

  Future<void> _restoreQueueState() async {
    if (_queueStateRestored) return;
    _queueStateRestored = true;

    // 使用通过 Riverpod 注入的 SharedPreferences 实例
    final prefs = _ref.read(sharedPreferencesProvider);
    final raw = prefs.getStringList(AppConstants.spQueueCacheKey);
    if (raw == null || raw.isEmpty) return;

    final cachedSongs = <Song>[];
    for (final item in raw) {
      try {
        final map = json.decode(item) as Map<String, dynamic>;
        cachedSongs.add(Song.fromManifest(map));
      } catch (_) {
        // skip bad entries
      }
    }
    if (cachedSongs.isEmpty) return;

    final savedIndex = prefs.getInt(AppConstants.spQueueIndexKey) ?? 0;
    final savedId = prefs.getInt(AppConstants.spQueueSongIdKey);
    final savedPositionMs = prefs.getInt(AppConstants.spQueuePositionKey) ?? 0;
    var index = savedIndex.clamp(0, cachedSongs.length - 1);
    if (savedId != null) {
      final byId = cachedSongs.indexWhere((s) => s.id == savedId);
      if (byId != -1) {
        index = byId;
      }
    }

    state = state.copyWith(
      queue: cachedSongs,
      currentIndex: index,
      currentSong: cachedSongs[index],
      isPlaying: false,
      position: Duration(milliseconds: savedPositionMs),
      duration: Duration.zero,
    );
    _syncBackgroundNowPlaying(cachedSongs[index]);

    _suppressIndexSync = true;
    final buildToken = ++_queueBuildToken;
    // 记录待恢复位置，待队列展开加载音源时通过 initialPosition 生效
    // （音源未加载前直接 seek 不会生效）
    if (savedPositionMs > 0) {
      _pendingRestorePosition = Duration(milliseconds: savedPositionMs);
    }
    _expandQueueInBackground(
      songs: cachedSongs,
      currentSongSnapshot: cachedSongs[index],
      buildToken: buildToken,
    );
  }

  Future<void> _persistQueueCache() async {
    final queue = state.queue;
    if (queue.isEmpty || state.currentIndex < 0) return;
    final prefs = _ref.read(sharedPreferencesProvider);
    final encoded = queue.map((s) => json.encode(s.toJson())).toList();
    await prefs.setStringList(AppConstants.spQueueCacheKey, encoded);
  }

  Future<void> _persistPlaybackState({bool includePosition = false}) async {
    final queue = state.queue;
    if (queue.isEmpty || state.currentIndex < 0) return;
    final prefs = _ref.read(sharedPreferencesProvider);
    await prefs.setInt(AppConstants.spQueueIndexKey, state.currentIndex);
    if (includePosition) {
      await prefs.setInt(
        AppConstants.spQueuePositionKey,
        state.position.inMilliseconds,
      );
    }
    if (state.currentSong != null) {
      await prefs.setInt(AppConstants.spQueueSongIdKey, state.currentSong!.id);
    }
  }

  Future<void> _expandQueueInBackground({
    required List<Song> songs,
    required Song currentSongSnapshot,
    required int buildToken,
  }) async {
    // 并发解析（本地文件/详情请求混合），保持原始顺序
    final entries = List<({Song song, AudioSource source})?>.filled(
      songs.length,
      null,
    );
    var cursor = 0;
    Future<void> worker() async {
      while (true) {
        final index = cursor++;
        if (index >= songs.length) return;
        if (!_mounted || buildToken != _queueBuildToken) return;
        entries[index] = await _buildPlayableEntry(songs[index]);
      }
    }

    const concurrency = 4;
    await Future.wait(
      List.generate(concurrency, (_) => worker(), growable: false),
    );

    final playableSongs = <Song>[];
    final sources = <AudioSource>[];
    for (final entry in entries) {
      if (entry == null) continue;
      playableSongs.add(entry.song);
      sources.add(entry.source);
    }

    if (!_mounted || buildToken != _queueBuildToken || playableSongs.isEmpty) {
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

    final resumePosition = _audioPlayer.playing
        ? _audioPlayer.position
        : _pendingRestorePosition;
    _pendingRestorePosition = Duration.zero;
    final shouldResume = _audioPlayer.playing;

    await _audioPlayer.setAudioSources(
      sources,
      initialIndex: currentIndex,
      initialPosition: resumePosition,
      preload: true,
    );

    if (!_mounted || buildToken != _queueBuildToken) return;

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
      final result = await _service.getSongDetails(resolvedSong.id);
      return result.when(
        ok: (details) async {
          _songDetailsCache[resolvedSong.id] = details;
          resolvedSong = _mergeSong(resolvedSong, details);
          final source = await _createAudioSource(resolvedSong);
          return (song: resolvedSong, source: source);
        },
        err: (error) {
          debugPrint('Skip unplayable song ${song.id}: ${error.message}');
          return null;
        },
      );
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
    final result = await _service.getSongDetails(songId);
    result.when(
      ok: (details) {
        _songDetailsCache[songId] = details;
        _mergeSongDetailsIntoState(details);
      },
      err: (error) {
        debugPrint('Failed to load song details for $songId: ${error.message}');
      },
    );
    _songDetailsLoading.remove(songId);
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
      hasCurrentSong: state.currentSong != null,
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

  Future<void> _maybePersistPosition() async {
    if (!_audioPlayer.playing) return;
    final now = DateTime.now();
    if (now.difference(_lastPositionPersist) < _positionPersistInterval) return;
    _lastPositionPersist = now;
    await _persistPlaybackState(includePosition: true);
  }

  /// 供 App 生命周期回调在退到后台时立即保存进度
  Future<void> persistPlaybackStateNow() async {
    _lastPositionPersist = DateTime.now();
    await _persistPlaybackState(includePosition: true);
  }

  // --- 通知栏 / 锁屏 / 耳机线控指令入口 ---
  @override
  void onPlay() => _audioPlayer.play();

  @override
  void onPause() => _audioPlayer.pause();

  @override
  void onSkipToNext() => next();

  @override
  void onSkipToPrevious() => previous();

  @override
  void onSeek(Duration position) => seek(position);

  @override
  void onStop() => stopPlayback();

  Future<void> setSpeed(double speed) async {
    await _audioPlayer.setSpeed(speed);
  }

  void togglePlayPause() {
    if (_audioPlayer.playing) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play();
    }
  }

  void stopPlayback() {
    _audioPlayer.stop();
    state = state.copyWith(isPlaying: false);
    _persistPlaybackState(includePosition: true);
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
