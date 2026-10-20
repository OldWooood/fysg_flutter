import 'dart:io';

import '../api/download_service.dart';
import '../models/song.dart';
import '../utils/app_log.dart';

/// 从 `PlayerNotifier` 抽出的下一首预取职责。
///
/// - 预取与正式下载共享 DownloadService 内的信号量槽位，
///   不再用全局 bool 丢弃第二次预取。
/// - 播放过半才触发，且同一切换只触发一次（_lastPrefetchSongId）。
/// - 预取就绪后通过 [onPrefetchReady] 回调通知播放器将队列中下一首的
///   网络音源热替换为本地预取文件，确保当前播放队列立即消费预取成果。
class PrefetchManager {
  PrefetchManager({required DownloadService downloads, this.onPrefetchReady})
    : _downloads = downloads;

  final DownloadService _downloads;
  final void Function(Song song, File file)? onPrefetchReady;
  bool _prefetchCacheLoaded = false;
  Set<int> _prefetchCachedIds = {};
  int? _lastPrefetchSongId;

  void resetForNewSong() => _lastPrefetchSongId = null;

  Future<void> _loadCacheIfNeeded() async {
    if (_prefetchCacheLoaded) return;
    _prefetchCachedIds = await _downloads.listPrefetchedSongIds();
    _prefetchCacheLoaded = true;
  }

  Future<File?> _usePrefetched(Song song) async {
    await _loadCacheIfNeeded();
    if (!_prefetchCachedIds.contains(song.id)) return null;
    if (!await _downloads.isPrefetched(song.id)) {
      _prefetchCachedIds.remove(song.id);
      return null;
    }
    return _downloads.getPrefetchFile(song.id);
  }

  Future<File?> _prefetch(Song song) async {
    try {
      await _loadCacheIfNeeded();
      if (await _downloads.isDownloaded(song.id)) {
        return await _downloads.getLocalFile(song.id);
      }
      await _downloads.prefetchSong(song);
      if (!await _downloads.isPrefetched(song.id)) return null;
      _prefetchCachedIds.add(song.id);
      return await _downloads.getPrefetchFile(song.id);
    } catch (e) {
      AppLog.d('Prefetch failed for song ${song.id}: $e');
      return null;
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
    _usePrefetched(nextSong).then((existingFile) async {
      final file = existingFile ?? await _prefetch(nextSong);
      if (file != null) {
        onPrefetchReady?.call(nextSong, file);
      }
    });
  }
}
