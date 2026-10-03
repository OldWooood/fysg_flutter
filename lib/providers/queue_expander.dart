import 'package:just_audio/just_audio.dart';

import '../api/asset_config.dart';
import '../api/download_service.dart';
import '../api/fysg_service.dart';
import '../models/song.dart';
import '../utils/app_log.dart';
import '../utils/constants.dart';
import 'song_resolver.dart';

/// 从 `PlayerNotifier` 抽出的队列展开职责（之前全在 1000 行上帝类里）。
///
/// - 共享调用方的详情缓存 Map（按引用传递，不另起一套）。
/// - 同步 IO 已消除：目录 Future 在 DownloadService 内缓存，
///   已下载 id 走内存索引，命中零 IO。
typedef PlayableEntry = ({Song song, AudioSource source});

class QueueExpander {
  QueueExpander({
    required FysgService service,
    required DownloadService downloads,
    required Map<int, Song> songDetailsCache,
    SongResolver resolver = const SongResolver(),
  }) : _service = service,
       _downloads = downloads,
       _songDetailsCache = songDetailsCache,
       _resolver = resolver;

  final FysgService _service;
  final DownloadService _downloads;
  final Map<int, Song> _songDetailsCache;
  final SongResolver _resolver;

  Future<AudioSource> createAudioSource(Song song) async {
    // 内存命中零 IO；未命中时 isDownloaded 内部落盘确认一次并回填
    if (await _downloads.isDownloaded(song.id)) {
      final local = await _downloads.getLocalFile(song.id);
      return AudioSource.file(local.path);
    }
    final prefetched = await _downloads.getPrefetchFile(song.id);
    if (await prefetched.exists()) {
      return AudioSource.file(prefetched.path);
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

  Future<PlayableEntry?> buildEntry(Song song, {bool refreshUrl = false}) async {
    var resolvedSong = song;
    // 冷启动恢复/首个音源失败时刷新播放地址：优先走网页端同款 songUrl 接口
    //（返回已编码的相对路径 + 当前 audioBase 拼接），失败再回退详情接口，
    // 还失败则用缓存 url 再试，避免直接用过期地址导致整队 setAudioSources 失败。
    if (refreshUrl && resolvedSong.id != 0) {
      final playUrls = await _service.getSongPlayUrls([resolvedSong.id]);
      final relative = playUrls.when(ok: (m) => m[resolvedSong.id], err: (_) => null);
      if (relative != null && relative.isNotEmpty) {
        final absolute = relative.startsWith('http')
            ? relative
            : '${AssetConfig.audioBase}$relative';
        resolvedSong = resolvedSong.copyWith(url: () => absolute);
      } else {
        final result = await _service.getSongDetails(resolvedSong.id);
        result.when(
          ok: (details) {
            _songDetailsCache[resolvedSong.id] = details;
            resolvedSong = _resolver.mergeSong(resolvedSong, details);
          },
          err: (error) {
            AppLog.d(
              'Refresh url failed for ${resolvedSong.id}, use cached: ${error.message}',
            );
          },
        );
      }
    }
    try {
      final source = await createAudioSource(resolvedSong);
      return (song: resolvedSong, source: source);
    } catch (_) {
      if (resolvedSong.id == 0) return null;
      final result = await _service.getSongDetails(resolvedSong.id);
      return await result.when(
        ok: (details) async {
          _songDetailsCache[resolvedSong.id] = details;
          final merged = _resolver.mergeSong(resolvedSong, details);
          try {
            final source = await createAudioSource(merged);
            return (song: merged, source: source);
          } catch (e) {
            AppLog.d('Skip unplayable song ${song.id}: $e');
            return null;
          }
        },
        err: (error) {
          AppLog.d('Skip unplayable song ${song.id}: ${error.message}');
          return null;
        },
      );
    }
  }

  /// 邻近优先的展开顺序：先当前及前后，首屏更快就绪。
  static List<int> expandOrder(int length, int startIndex) {
    final order = <int>[];
    final start = startIndex.clamp(0, length - 1);
    for (var offset = 0; offset < length; offset++) {
      final fwd = start + offset;
      if (fwd < length) order.add(fwd);
      final back = start - offset;
      if (offset != 0 && back >= 0) order.add(back);
      if (order.length >= length) break;
    }
    return order;
  }
}
