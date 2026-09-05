import 'dart:async';

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
import 'queue_persistence.dart';
import 'shared_preferences_provider.dart';
import 'song_resolver.dart';

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

// Riverpod 3：StateNotifierProvider/StateNotifier 已移除，改用 NotifierProvider。
// 依赖改在 build() 内用 ref.watch 获取（实例在 build 重跑时保留，仅 state 会重置；
// 下方 service 均为稳定单例，不会触发重跑）。
final playerProvider = NotifierProvider<PlayerNotifier, FysgPlayerState>(
  PlayerNotifier.new,
);

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

class PlayerNotifier extends Notifier<FysgPlayerState>
    implements AppAudioHandlerDelegate {
  final AudioPlayer _audioPlayer = AudioPlayer();
  late final FysgService _service;
  late final DownloadService _downloadService;
  late final RecentlyPlayedService _recentService;
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
  int _consecutiveAutoSkips = 0;
  late final QueuePersistence _persistence;
  static const _songResolver = SongResolver();

  /// 冷启动恢复队列时待使用的续播位置，
  /// 在队列展开完成、真正加载音源时一次性消费
  Duration _pendingRestorePosition = Duration.zero;

  /// 播放中定期持久化进度的间隔，避免频繁写 SharedPreferences
  static const _positionPersistInterval = Duration(seconds: 5);

  // Stream 订阅管理，防止内存泄漏
  final List<StreamSubscription> _subscriptions = [];
  bool _isDisposed = false;
  bool _initialized = false;

  @override
  FysgPlayerState build() {
    _service = ref.watch(fysgServiceProvider);
    _downloadService = ref.watch(downloadServiceProvider);
    _recentService = ref.watch(recentlyPlayedServiceProvider);
    _persistence = QueuePersistence(ref);
    // build 重跑时实例保留：只初始化一次，避免重复订阅/恢复队列
    if (!_initialized) {
      _initialized = true;
      _init();
      // Notifier 没有可 override 的 dispose（同步），cancel 的 Future 无法 await，
      // 用 unawaited 显式标记“故意不等待”；同时解绑音频通知 delegate，
      // 防止静态单例持有已释放对象。
      ref.onDispose(() {
        _isDisposed = true;
        for (final subscription in _subscriptions) {
          unawaited(subscription.cancel());
        }
        _subscriptions.clear();
        AppAudioService.handler?.detachDelegate(this);
        _persistence.dispose();
        unawaited(_audioPlayer.dispose());
      });
    }
    return const FysgPlayerState();
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
            _consecutiveAutoSkips = 0;
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

    // 注：之前这里有个空 playbackEventStream 监听只为 debug，
    // just_audio 的 LoopMode 已处理 completed 自动下一首，无需手动监听；
    // 真正的播放错误走 playerStateStream/各 onError + _handleSongLoadFailure。
    // 如需排查卡顿，可临时加回带 debugPrint 的监听，不要提交空监听。

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
    // 单曲队列下无下一首可跳，避免 next(auto:true) 死循环跳歌
    if (state.queue.length <= 1) {
      debugPrint(
        'Single-song queue, stop retry for ${currentSong.id}, reason: $reason',
      );
      _songLoadRetryCount[currentSong.id] = 0;
      return;
    }

    final retries = (_songLoadRetryCount[currentSong.id] ?? 0) + 1;
    _songLoadRetryCount[currentSong.id] = retries;

    if (retries <= AppConstants.maxSongLoadRetries) {
      debugPrint(
        'Retry loading song ${currentSong.id} ($retries/${AppConstants.maxSongLoadRetries}), reason: $reason',
      );
      try {
        await _audioPlayer.seek(Duration.zero);
        await _audioPlayer.play();
        _consecutiveAutoSkips = 0;
        return;
      } catch (e) {
        debugPrint('Retry failed for song ${currentSong.id}: $e');
      }
    }

    // 连续自动跳歌熔断：重试耗尽的坏资源连续出现时停下来，而不是无限 next()
    _consecutiveAutoSkips++;
    if (_consecutiveAutoSkips > AppConstants.maxConsecutiveAutoSkips) {
      debugPrint(
        'Too many consecutive auto-skips ($_consecutiveAutoSkips), stop auto-next',
      );
      _songLoadRetryCount[currentSong.id] = 0;
      return;
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

  /// 同步 IO（existsSync）会阻塞 UI 线程，全部改为异步 exists()。
  Future<AudioSource> _createAudioSource(Song song) async {
    final prefetched = await _downloadService.getPrefetchFile(song.id);
    if (await prefetched.exists()) {
      _prefetchCachedIds.add(song.id);
      return AudioSource.file(prefetched.path);
    }

    final localFile = await _downloadService.getLocalFile(song.id);

    if (await localFile.exists()) {
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
            if (_mounted) ref.invalidate(downloadedSongsProvider);
          })
          .catchError((Object e) {
            // 之前这里只 debugPrint，用户无感知；现打日志并可由 UI toast
            debugPrint('Download error: $e');
          });

      return DownloadResult.started;
    } catch (e) {
      debugPrint('Download error: $e');
      return DownloadResult.failed;
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
    ref.invalidate(recentSongsProvider);
  }

  Future<void> restoreCachedQueue() async {
    await _restoreQueueState();
  }

  Future<void> _restoreQueueState() async {
    if (_queueStateRestored) return;
    _queueStateRestored = true;

    // 使用通过 Riverpod 注入的 SharedPreferences 实例
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getStringList(AppConstants.spQueueCacheKey);
    if (raw == null || raw.isEmpty) return;

    final cachedSongs = decodeCachedQueue(raw);
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
    if (state.queue.isEmpty || state.currentIndex < 0) return;
    _persistence.schedulePersistQueueCache(state.queue);
  }

  Future<void> _persistPlaybackState({bool includePosition = false}) async {
    if (state.queue.isEmpty || state.currentIndex < 0) return;
    if (includePosition) {
      // 含位置的关键写立即落盘；纯 index 写走防抖
      await _persistence.persistPlaybackStateNow(
        currentIndex: state.currentIndex,
        currentSongId: state.currentSong?.id,
        positionMs: state.position.inMilliseconds,
        includePosition: true,
      );
    } else {
      _persistence.schedulePersistPlaybackState(
        currentIndex: state.currentIndex,
        currentSongId: state.currentSong?.id,
        positionMs: state.position.inMilliseconds,
      );
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

  Song _mergeSong(Song base, Song details) =>
      _songResolver.mergeSong(base, details);

  bool _isSameSong(Song a, Song b) => _songResolver.isSameSong(a, b);

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
    if (state.queue.length <= 1) {
      // 单曲队列下 seekToNext 无意义，直接重播当前
      _audioPlayer.seek(Duration.zero);
      if (auto) _audioPlayer.play();
      return;
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

enum DownloadResult { started, alreadyDownloaded, failed }
