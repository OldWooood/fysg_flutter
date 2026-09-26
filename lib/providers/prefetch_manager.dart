import '../api/download_service.dart';
import '../models/song.dart';
import '../utils/app_log.dart';

/// 从 `PlayerNotifier` 抽出的下一首预取职责。
///
/// - 预取与正式下载共享 DownloadService 内的信号量槽位，
///   不再用全局 bool 丢弃第二次预取。
/// - 播放过半才触发，且同一切换只触发一次（_lastPrefetchSongId）。
class PrefetchManager {
  PrefetchManager({required DownloadService downloads}) : _downloads = downloads;

  final DownloadService _downloads;
  bool _prefetchCacheLoaded = false;
  Set<int> _prefetchCachedIds = {};
  int? _lastPrefetchSongId;

  void resetForNewSong() => _lastPrefetchSongId = null;

  Future<void> _loadCacheIfNeeded() async {
    if (_prefetchCacheLoaded) return;
    _prefetchCachedIds = await _downloads.listPrefetchedSongIds();
    _prefetchCacheLoaded = true;
  }

  Future<bool> _usePrefetched(Song song) async {
    await _loadCacheIfNeeded();
    if (!_prefetchCachedIds.contains(song.id)) return false;
    if (!await _downloads.isPrefetched(song.id)) {
      _prefetchCachedIds.remove(song.id);
      return false;
    }
    return true;
  }

  Future<void> _prefetch(Song song) async {
    try {
      await _loadCacheIfNeeded();
      if (await _downloads.isDownloaded(song.id)) return;
      await _downloads.prefetchSong(song);
      _prefetchCachedIds.add(song.id);
    } catch (e) {
      AppLog.d('Prefetch failed for song ${song.id}: $e');
    }
  }

  /// 播放过半且队列 ≥2 首时预取下一首；调用方传入按模式算好的 nextSong。
  void maybePrefetch({
    required Duration position,
    required Duration duration,
    required List<Song> queue,
    required Song? nextSong,
  }) {
    final durationMs = duration.inMilliseconds;
    if (durationMs <= 0) return;
    if (position.inMilliseconds < durationMs ~/ 2) return;
    if (queue.length < 2) return;
    if (nextSong == null) return;
    if (_lastPrefetchSongId == nextSong.id) return;

    _lastPrefetchSongId = nextSong.id;
    _usePrefetched(nextSong).then((used) {
      if (!used) _prefetch(nextSong);
    });
  }
}
