import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import '../providers/shared_preferences_provider.dart';
import '../utils/constants.dart';

final recentlyPlayedServiceProvider = Provider((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return RecentlyPlayedService(prefs);
});

final recentSongsProvider = FutureProvider<List<Song>>((ref) async {
  return ref.watch(recentlyPlayedServiceProvider).getRecentSongs();
});

class RecentlyPlayedService {
  static const int _maxSongs = 500;
  static const _persistDebounce = Duration(seconds: 2);
  final SharedPreferences _prefs;

  RecentlyPlayedService(this._prefs);

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

  Future<void> addSong(Song song) async {
    final cache = _memoryCache ??= _loadFromDisk();
    cache.removeWhere((s) => s.id == song.id);
    // 内存保留完整对象（含歌词），落盘只存轻快照
    cache.insert(0, song);
    if (cache.length > _maxSongs) {
      cache.removeRange(_maxSongs, cache.length);
    }
    _pendingJson = cache.map((s) => json.encode(s.toCacheJson())).toList();

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

  Future<List<Song>> getRecentSongs() async {
    // 内存命中则零 IO 返回，避免首页+我的同时 watch 重复读盘
    final cache = _memoryCache;
    if (cache != null) return List<Song>.from(cache);
    _memoryCache = _loadFromDisk();
    return List<Song>.from(_memoryCache!);
  }

  void dispose() {
    _persistTimer?.cancel();
  }
}
