import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../utils/constants.dart';
import 'shared_preferences_provider.dart';

/// 从上帝类 `PlayerNotifier` 抽出的队列持久化职责：
///
/// - 之前每次切歌都全量 `json.encode(整个queue)` + `setStringList`，
///   大队列下是 O(n) 主线程序列化；现加 500ms 防抖合并写盘。
/// - 脏 manifest 条目跳过，不抛异常。
class QueuePersistence {
  QueuePersistence(this._ref);

  final Ref _ref;
  Timer? _queueDebounce;
  Timer? _stateDebounce;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _queueDebounce?.cancel();
    _stateDebounce?.cancel();
  }

  /// 立即写队列快照（冷启动恢复/切歌首帧用），防抖写走 schedule 系方法。
  Future<void> persistQueueCacheNow(List<Song> queue) async {
    if (_disposed || queue.isEmpty) return;
    try {
      final prefs = _ref.read(sharedPreferencesProvider);
      final encoded = queue.map((s) => json.encode(s.toJson())).toList();
      await prefs.setStringList(AppConstants.spQueueCacheKey, encoded);
    } catch (_) {
      // 写缓存失败不影响播放，忽略
    }
  }

  void schedulePersistQueueCache(List<Song> queue) {
    _queueDebounce?.cancel();
    final snapshot = List<Song>.from(queue);
    _queueDebounce = Timer(AppConstants.queuePersistDebounce, () {
      persistQueueCacheNow(snapshot);
    });
  }

  Future<void> persistPlaybackStateNow({
    required int currentIndex,
    required int? currentSongId,
    required int positionMs,
    required bool includePosition,
  }) async {
    if (_disposed || currentIndex < 0) return;
    try {
      final prefs = _ref.read(sharedPreferencesProvider);
      await prefs.setInt(AppConstants.spQueueIndexKey, currentIndex);
      if (includePosition) {
        await prefs.setInt(AppConstants.spQueuePositionKey, positionMs);
      }
      if (currentSongId != null) {
        await prefs.setInt(AppConstants.spQueueSongIdKey, currentSongId);
      }
    } catch (_) {
      // 忽略持久化失败
    }
  }

  void schedulePersistPlaybackState({
    required int currentIndex,
    required int? currentSongId,
    required int positionMs,
    bool includePosition = false,
  }) {
    _stateDebounce?.cancel();
    _stateDebounce = Timer(AppConstants.queuePersistDebounce, () {
      persistPlaybackStateNow(
        currentIndex: currentIndex,
        currentSongId: currentSongId,
        positionMs: positionMs,
        includePosition: includePosition,
      );
    });
  }
}

/// 冷启动恢复时解析缓存队列，脏数据逐条跳过。
List<Song> decodeCachedQueue(List<String> raw) {
  final cachedSongs = <Song>[];
  for (final item in raw) {
    try {
      final map = json.decode(item);
      if (map is Map<String, dynamic>) {
        cachedSongs.add(Song.fromManifest(map));
      } else if (map is Map) {
        cachedSongs.add(Song.fromManifest(Map<String, dynamic>.from(map)));
      }
    } catch (_) {
      // skip bad entries
    }
  }
  return cachedSongs;
}
