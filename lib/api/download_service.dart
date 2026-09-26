import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import '../providers/shared_preferences_provider.dart';
import '../utils/constants.dart';

final downloadServiceProvider = Provider((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final service = DownloadService(prefs);
  ref.onDispose(service.dispose);
  return service;
});

/// 已下载歌曲列表（下载完成/删除后通过 invalidate 刷新）
final downloadedSongsProvider = FutureProvider.autoDispose<List<Song>>(((
  ref,
) async {
  return ref.watch(downloadServiceProvider).getDownloadedSongs();
}));

/// 简单信号量：替代之前的 `while + delay(200ms)` 忙等。
class _Semaphore {
  _Semaphore(this._slots);

  int _slots;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<void> acquire() {
    if (_slots > 0) {
      _slots--;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void release() {
    final waiter = _waiters.isEmpty ? null : _waiters.removeFirst();
    if (waiter != null) {
      waiter.complete();
    } else {
      _slots++;
    }
  }
}

class DownloadService {
  late final Dio _dio;
  final SharedPreferences _prefs;
  // 下载取消 + 并发控制：之前无 CancelToken、无上限，连续点多首打满带宽
  final Map<int, CancelToken> _activeTokens = {};
  final Map<int, CancelToken> _prefetchTokens = {};
  late final _Semaphore _slots = _Semaphore(
    AppConstants.maxConcurrentDownloads,
  );

  // 已下载 id 内存索引：命中则零 IO；未命中再落盘确认并回填。
  // （之前每次播放都要 exists() 走一次 IO）
  final Set<int> _downloadedIds = {};

  // 目录 Future 缓存：之前每次 getLocalFile 都走一次 platform channel
  Future<Directory>? _docDirFuture;
  Future<Directory>? _tmpDirFuture;
  Future<Directory>? _prefetchDirFuture;

  DownloadService(this._prefs) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: AppConstants.downloadConnectTimeout,
        receiveTimeout: AppConstants.downloadReceiveTimeout,
        headers: AppConstants.defaultHeaders,
      ),
    );
  }

  void dispose() {
    for (final token in _activeTokens.values) {
      try {
        token.cancel('dispose');
      } catch (_) {}
    }
    for (final token in _prefetchTokens.values) {
      try {
        token.cancel('dispose');
      } catch (_) {}
    }
    _activeTokens.clear();
    _prefetchTokens.clear();
    _dio.close(force: true);
  }

  void cancelDownload(int songId) {
    _activeTokens[songId]?.cancel('user cancel');
    _prefetchTokens[songId]?.cancel('user cancel');
  }

  Future<Directory> _docDir() =>
      _docDirFuture ??= getApplicationDocumentsDirectory();
  Future<Directory> _tmpDir() => _tmpDirFuture ??= getTemporaryDirectory();
  Future<Directory> _prefetchDir() => _prefetchDirFuture ??= _tmpDir().then(
    (tmp) => Directory('${tmp.path}/prefetch'),
  );

  Future<File> _ensureParentExists(File file) async {
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    return file;
  }

  Future<File> getLocalFile(int songId) async {
    final dir = await _docDir();
    return File('${dir.path}/songs/$songId.mp3');
  }

  Future<File> getPrefetchFile(int songId) async {
    final dir = await _prefetchDir();
    return File('${dir.path}/$songId.mp3');
  }

  Future<File> getPrefetchTempFile(int songId) async {
    final dir = await _prefetchDir();
    return File('${dir.path}/$songId.part');
  }

  Future<bool> isPrefetched(int songId) async {
    final file = await getPrefetchFile(songId);
    return file.exists();
  }

  Future<void> deletePrefetch(int songId) async {
    final file = await getPrefetchFile(songId);
    if (await file.exists()) {
      await file.delete();
    }
    final tempFile = await getPrefetchTempFile(songId);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    await _removePrefetchIndex(songId);
  }

  /// 预取：与其他下载共享信号量槽位，支持取消，避免无上限并发打满带宽。
  Future<void> prefetchSong(
    Song song, {
    void Function(int, int)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (song.url == null) return;

    final finalFile = await getPrefetchFile(song.id);
    if (await finalFile.exists()) return;
    if (!await finalFile.parent.exists()) {
      await finalFile.parent.create(recursive: true);
    }

    final tempFile = await getPrefetchTempFile(song.id);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final token = cancelToken ?? CancelToken();
    _prefetchTokens[song.id] = token;
    await _slots.acquire();
    try {
      await _downloadToFile(
        song.url!,
        tempFile.path,
        onProgress: onProgress,
        cancelToken: token,
      );
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tempFile.rename(finalFile.path);
      await _addPrefetchIndex(song.id);
      await enforcePrefetchLimit();
    } catch (_) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      _slots.release();
      if (_prefetchTokens[song.id] == token) {
        _prefetchTokens.remove(song.id);
      }
    }
  }

  Future<void> enforcePrefetchLimit({
    int maxBytes = AppConstants.prefetchMaxBytes,
  }) async {
    final dir = await _prefetchDir();
    if (!await dir.exists()) return;

    final files = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.mp3')) {
        files.add(entity);
      }
    }
    if (files.isEmpty) return;

    final stats = <File, FileStat>{};
    var totalBytes = 0;
    for (final file in files) {
      final stat = await file.stat();
      stats[file] = stat;
      totalBytes += stat.size;
    }
    if (totalBytes <= maxBytes) return;

    files.sort((a, b) {
      final at = stats[a]?.modified.millisecondsSinceEpoch ?? 0;
      final bt = stats[b]?.modified.millisecondsSinceEpoch ?? 0;
      return at.compareTo(bt);
    });

    for (final file in files) {
      if (totalBytes <= maxBytes) break;
      final size = stats[file]?.size ?? 0;
      try {
        final name = file.uri.pathSegments.last;
        if (name.endsWith('.mp3')) {
          final idPart = name.substring(0, name.length - 4);
          final id = int.tryParse(idPart);
          if (id != null) {
            await _removePrefetchIndex(id);
          }
        }
        await file.delete();
        totalBytes -= size;
      } catch (_) {
        // ignore delete failures
      }
    }
  }

  Future<Set<int>> listPrefetchedSongIds() async {
    final raw = _prefs.getStringList(AppConstants.spPrefetchIndexKey) ?? [];
    return raw.map(int.tryParse).whereType<int>().toSet();
  }

  Future<void> _addPrefetchIndex(int songId) async {
    final raw = _prefs.getStringList(AppConstants.spPrefetchIndexKey) ?? [];
    final exists = raw.any((id) => id == songId.toString());
    if (exists) return;
    raw.add(songId.toString());
    await _prefs.setStringList(AppConstants.spPrefetchIndexKey, raw);
  }

  Future<void> _removePrefetchIndex(int songId) async {
    final raw = _prefs.getStringList(AppConstants.spPrefetchIndexKey) ?? [];
    raw.removeWhere((id) => id == songId.toString());
    await _prefs.setStringList(AppConstants.spPrefetchIndexKey, raw);
  }

  Future<void> downloadSong(
    Song song, {
    void Function(int, int)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (song.url == null) return;

    // 信号量限流：超过上限排队等待，不再忙等轮询
    final token = cancelToken ?? CancelToken();
    _activeTokens[song.id] = token;
    await _slots.acquire();
    try {
      final file = await getLocalFile(song.id);
      await _ensureParentExists(file);
      // 原子写：先 .part 再 rename，杀进程不留残缺 mp3
      final partFile = File('${file.path}.part');
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
      await _downloadToFile(
        song.url!,
        partFile.path,
        onProgress: onProgress,
        cancelToken: token,
      );
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      await partFile.rename(file.path);
      _downloadedIds.add(song.id);

      // Save to manifest（轻快照去歌词）
      await _saveToManifest(song);
    } finally {
      _slots.release();
      if (_activeTokens[song.id] == token) {
        _activeTokens.remove(song.id);
      }
    }
  }

  /// 带重试 + 指数退避的下载：之前无重试、无超时，弱网永久挂起且异常直接 rethrow
  Future<void> _downloadToFile(
    String url,
    String path, {
    void Function(int, int)? onProgress,
    CancelToken? cancelToken,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < AppConstants.downloadMaxRetries; attempt++) {
      try {
        await _dio.download(
          url,
          path,
          onReceiveProgress: onProgress,
          cancelToken: cancelToken,
          options: Options(headers: AppConstants.defaultHeaders),
        );
        return;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) rethrow;
        lastError = e;
        // 最后一试失败则清理残缺文件后抛出可读错误
        if (attempt == AppConstants.downloadMaxRetries - 1) {
          try {
            final partial = File(path);
            if (await partial.exists()) await partial.delete();
          } catch (_) {}
          throw Exception(
            '下载失败(${e.type.name})：${e.message ?? url}，已重试$attempt次',
          );
        }
        await Future.delayed(Duration(seconds: 1 << attempt));
      }
    }
    if (lastError != null) throw lastError;
  }

  /// 安全解析 manifest 条目：脏数据返回 null 而不是抛 FormatException
  Map<String, dynamic>? _safeDecodeManifest(String item) {
    try {
      final map = json.decode(item);
      if (map is Map<String, dynamic>) return map;
      if (map is Map) return Map<String, dynamic>.from(map);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToManifest(Song song) async {
    final List<String> downloaded =
        _prefs.getStringList(AppConstants.spDownloadedSongs) ?? [];

    var exists = false;
    for (final item in downloaded) {
      final map = _safeDecodeManifest(item);
      if (map != null && map['id'] == song.id) {
        exists = true;
        break;
      }
    }

    if (!exists) {
      downloaded.add(json.encode(song.toCacheJson()));
      await _prefs.setStringList(AppConstants.spDownloadedSongs, downloaded);
    }
  }

  Future<List<Song>> getDownloadedSongs() async {
    final List<String> downloaded =
        _prefs.getStringList(AppConstants.spDownloadedSongs) ?? [];

    final parsed = <Song>[];
    for (final item in downloaded) {
      final map = _safeDecodeManifest(item);
      if (map == null) continue;
      try {
        parsed.add(Song.fromManifest(map));
      } catch (_) {
        continue;
      }
    }
    if (parsed.isEmpty) {
      if (downloaded.isNotEmpty) {
        await _prefs.setStringList(AppConstants.spDownloadedSongs, []);
      }
      return [];
    }

    // 并行 exists：之前串行 N 次 IO，100 首首开慢
    final checks = await Future.wait(
      parsed.map((song) async {
        try {
          final file = await getLocalFile(song.id);
          return (song: song, exists: await file.exists());
        } catch (_) {
          return (song: song, exists: false);
        }
      }),
    );

    final songs = <Song>[];
    final validFiles = <String>[];
    final rawById = <int, String>{};
    for (final item in downloaded) {
      final map = _safeDecodeManifest(item);
      final id = map?['id'];
      final idInt = id is int ? id : int.tryParse('$id');
      if (idInt != null) rawById[idInt] = item;
    }
    for (final c in checks) {
      if (c.exists) {
        songs.add(c.song);
        _downloadedIds.add(c.song.id);
        final raw = rawById[c.song.id];
        if (raw != null) validFiles.add(raw);
      }
    }

    if (validFiles.length != downloaded.length) {
      await _prefs.setStringList(AppConstants.spDownloadedSongs, validFiles);
    }

    return songs;
  }

  /// 内存优先的已下载判断：命中内存零 IO，未命中再落盘并回填。
  Future<bool> isDownloaded(int songId) async {
    if (_downloadedIds.contains(songId)) return true;
    final file = await getLocalFile(songId);
    final exists = await file.exists();
    if (exists) _downloadedIds.add(songId);
    return exists;
  }

  void markDownloaded(int songId) => _downloadedIds.add(songId);

  Future<void> deleteDownload(int songId) async {
    final file = await getLocalFile(songId);
    if (await file.exists()) {
      await file.delete();
    }
    _downloadedIds.remove(songId);

    final List<String> downloaded =
        _prefs.getStringList(AppConstants.spDownloadedSongs) ?? [];
    downloaded.removeWhere((item) {
      final map = _safeDecodeManifest(item);
      if (map == null) return true; // 脏数据顺手清理
      return map['id'] == songId;
    });
    await _prefs.setStringList(AppConstants.spDownloadedSongs, downloaded);
  }
}
