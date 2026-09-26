import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';
import '../utils/app_log.dart';
import '../utils/constants.dart';
import 'shared_preferences_provider.dart';

/// 从上帝类 `PlayerNotifier` 抽出的队列持久化职责：
///
/// - 之前每次切歌都全量 `json.encode(整个queue)` + `setStringList`，
///   大队列下是 O(n) 主线程序列化；现加 500ms 防抖合并写盘。
/// - 脏 manifest 条目跳过，不抛异常。
/// - 队列快照改存单文件 `queue_cache.json`（单次写盘），不再用
///   SharedPreferences StringList（大列表易超限且读写慢）；
///   首次读取自动迁移旧 SP 数据并清理旧 key。
/// - 统一截断到 [AppConstants.maxQueueItems]，避免 500 首快照撑爆磁盘。
class QueuePersistence {
  QueuePersistence(this._ref);

  final Ref _ref;
  Future<File>? _cacheFileFuture;
  Timer? _queueDebounce;
  Timer? _stateDebounce;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _queueDebounce?.cancel();
    _stateDebounce?.cancel();
  }

  Future<File> _cacheFile() => _cacheFileFuture ??= getApplicationDocumentsDirectory()
      .then((dir) => File('${dir.path}/queue_cache.json'));

  List<Song> _cap(List<Song> queue) => queue.length <= AppConstants.maxQueueItems
      ? queue
      : queue.sublist(0, AppConstants.maxQueueItems);

  /// 立即写队列快照（冷启动恢复/切歌首帧用），防抖写走 schedule 系方法。
  Future<void> persistQueueCacheNow(List<Song> queue) async {
    if (_disposed || queue.isEmpty) return;
    try {
      final capped = _cap(queue);
      // 轻量快照去歌词：500 首 * 几十KB LRC 会撑爆 SP 且启动 decode 卡顿
      final encoded = json.encode(
        capped.map((s) => s.toCacheJson()).toList(),
      );
      final file = await _cacheFile();
      await file.writeAsString(encoded, flush: true);
      // 迁移清理：文件写成功后删掉旧 SP 大 key
      try {
        final prefs = _ref.read(sharedPreferencesProvider);
        if (prefs.containsKey(AppConstants.spQueueCacheKey)) {
          await prefs.remove(AppConstants.spQueueCacheKey);
        }
      } catch (_) {}
    } catch (e) {
      AppLog.d('persistQueueCache failed: $e');
    }
  }

  void schedulePersistQueueCache(List<Song> queue) {
    _queueDebounce?.cancel();
    final snapshot = List<Song>.from(_cap(queue));
    _queueDebounce = Timer(AppConstants.queuePersistDebounce, () {
      persistQueueCacheNow(snapshot);
    });
  }

  /// 启动恢复统一入口：优先读文件，缺失再回退旧 SP 并迁移。
  Future<List<Song>> loadQueueCache() async {
    try {
      final file = await _cacheFile();
      if (await file.exists()) {
        final raw = await file.readAsString();
        final songs = decodeCachedQueueJson(raw);
        if (songs.isNotEmpty) return _cap(songs);
      }
    } catch (e) {
      AppLog.d('loadQueueCache file failed: $e');
    }
    try {
      final prefs = _ref.read(sharedPreferencesProvider);
      final raw = prefs.getStringList(AppConstants.spQueueCacheKey);
      if (raw == null || raw.isEmpty) return const [];
      final songs = decodeCachedQueue(raw);
      if (songs.isNotEmpty) {
        // 顺手迁移到文件，下次不再读 SP
        await persistQueueCacheNow(songs);
      }
      return _cap(songs);
    } catch (e) {
      AppLog.d('loadQueueCache legacy failed: $e');
      return const [];
    }
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

/// 新文件格式：单个 JSON 数组字符串。
List<Song> decodeCachedQueueJson(String raw) {
  try {
    final decoded = json.decode(raw);
    if (decoded is! List) return const [];
    final songs = <Song>[];
    for (final item in decoded) {
      try {
        if (item is Map<String, dynamic>) {
          songs.add(Song.fromManifest(item));
        } else if (item is Map) {
          songs.add(Song.fromManifest(Map<String, dynamic>.from(item)));
        }
      } catch (_) {
        // skip bad entries
      }
    }
    return songs;
  } catch (_) {
    return const [];
  }
}
