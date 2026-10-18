import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import '../providers/shared_preferences_provider.dart';
import '../utils/constants.dart';

final recentlyPlayedServiceProvider = Provider((ref) {
  final service = RecentlyPlayedService(ref.watch(sharedPreferencesProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// 最近播放（内存态列表）。
///
/// 之前是 FutureProvider + 每次切歌 `ref.invalidate`：整个 provider 重建 +
/// 最多 500 条列表复制 + 所有订阅区块重建。现改为 Notifier 内存增删，
/// 只有真正变化的列表实例被替换，落盘仍由 service 防抖合并。
final recentSongsProvider = NotifierProvider<RecentSongsNotifier, List<Song>>(
  RecentSongsNotifier.new,
);

class RecentSongsNotifier extends Notifier<List<Song>> {
  @override
  List<Song> build() {
    return List<Song>.unmodifiable(
      ref.watch(recentlyPlayedServiceProvider).snapshot(),
    );
  }

  /// 播放入口调用：去重置顶 + 上限截断，一次 O(n) 更新状态；
  /// 落盘交给 [RecentlyPlayedService.schedulePersist] 防抖。
  void add(Song song) {
    final next = <Song>[song, ...state.where((s) => s.id != song.id)];
    if (next.length > RecentlyPlayedService.maxSongs) {
      next.removeRange(RecentlyPlayedService.maxSongs, next.length);
    }
    state = List<Song>.unmodifiable(next);
    ref.read(recentlyPlayedServiceProvider).schedulePersist(next);
  }
}

class RecentlyPlayedService {
  static const int maxSongs = 500;
  final SharedPreferences _prefs;

  /// [persistDebounce] 仅测试可缩短；生产用 2s 合并连续切歌。
  RecentlyPlayedService(
    this._prefs, {
    Duration persistDebounce = const Duration(seconds: 2),
  }) : _persistDebounce = persistDebounce;

  final Duration _persistDebounce;

  // 内存缓存 + 防抖落盘：之前每次切歌全量 decode 500 条(含歌词) + encode，
  // 主线程几十ms。现内存增量更新，2s 合并写一次。
  List<Song>? _memoryCache;
  Timer? _persistTimer;
  List<String>? _pendingJson;

  List<Song> _loadFromDisk() {
    final songsJson = _prefs.getStringList(AppConstants.spRecentSongs) ?? [];
    return songsJson
        .map((item) {
          try {
            final map = json.decode(item) as Map<String, dynamic>;
            return Song.fromManifest(map);
          } catch (_) {
            return null;
          }
        })
        .whereType<Song>()
        .toList();
  }

  /// 同步快照：内存命中零 IO；首次访问逐条容错 decode。
  /// 同步是刻意的——首帧即可拿到列表，不再 async 闪空。
  List<Song> snapshot() => _memoryCache ??= _loadFromDisk();

  /// 防抖落盘：连续切歌只写一次；轻快照去歌词。
  void schedulePersist(List<Song> songs) {
    _pendingJson = songs.map((s) => json.encode(s.toCacheJson())).toList();

    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, () async {
      final pending = _pendingJson;
      if (pending == null) return;
      _pendingJson = null;
      try {
        await _prefs.setStringList(AppConstants.spRecentSongs, pending);
      } catch (_) {
        // 忽略持久化失败
      }
    });
  }

  void dispose() {
    _persistTimer?.cancel();
  }
}
