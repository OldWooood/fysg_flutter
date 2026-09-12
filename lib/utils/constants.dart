/// 应用常量配置
///
/// 后端地址支持 `--dart-define` 覆盖，便于切换测试/生产环境：
/// `flutter run --dart-define=FYSG_API_BASE=https://test.example.com`
class AppConstants {
  AppConstants._();

  // API 相关（可用 dart-define 覆盖，避免写死后一改版全挂）
  static const String apiBaseUrl = String.fromEnvironment(
    'FYSG_API_BASE',
    defaultValue: 'https://www.fysg.org',
  );
  static const String assetBaseUrl = String.fromEnvironment(
    'FYSG_ASSET_BASE',
    defaultValue: 'https://sg-file.nanqiao.xyz',
  );
  static const String apiVersion = '5.1.7';
  static const String apiAppName = 'fuyinshige';
  static const String apiDevice = 'web';

  // 网络超时：之前全无 timeout，弱网会永久挂起
  static const Duration networkTimeout = Duration(seconds: 12);
  static const Duration downloadConnectTimeout = Duration(seconds: 15);
  static const Duration downloadReceiveTimeout = Duration(minutes: 5);
  static const int downloadMaxRetries = 3;

  // 默认请求头
  // 注：后端要求浏览器 Referer/Origin 才会放行，此处保留 UA 伪装并集中管理。
  static const Map<String, String> defaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Referer': 'https://www.fysg.org/',
    'Origin': 'https://www.fysg.org',
  };

  // 缓存时间
  static const Duration searchCacheTtl = Duration(seconds: 45);
  static const Duration recommendCacheTtl = Duration(minutes: 2);

  // SharedPreferences Keys
  static const String spDownloadedSongs = 'downloaded_songs';
  static const String spPrefetchIndexKey = 'prefetch_song_ids';
  static const String spQueueCacheKey = 'player_queue_cache';
  static const String spQueueIndexKey = 'player_queue_index';
  static const String spQueueSongIdKey = 'player_queue_song_id';
  static const String spQueuePositionKey = 'player_queue_position_ms';
  static const String spSearchHistory = 'search_history';
  static const String spRecentSongs = 'recent_songs';
  static const String spFavoritePlaylists = 'favorite_playlists';

  // 分页
  static const int defaultPageSize = 20;
  static const int defaultPage = 0;

  // 音频相关
  static const int maxSongLoadRetries = 2;
  static const int maxConsecutiveAutoSkips = 3;
  static const int prefetchMaxBytes = 256 * 1024 * 1024; // 256MB

  // 持久化防抖：切歌时全量 json.encode 大队列很贵，合并写盘
  static const Duration queuePersistDebounce = Duration(milliseconds: 500);

  // 播放页取色缓存上限（之前无界静态 Map，切歌越多内存越大）
  static const int paletteCacheMaxEntries = 30;

  // UI 相关
  static const double loadMoreTriggerExtent = 600.0;
  static const double miniPlayerHeight = 80.0;
  static const Duration searchDebounceMs = Duration(milliseconds: 300);
  // 列表预构建范围：之前全 800，过大；按机型取 250~500
  static const double listCacheExtent = 400.0;

  // 图片磁盘缓存：长列表 + 大封面双解码，限制数量与有效期
  static const int imageCacheMaxObjects = 200;
  static const Duration imageCacheStalePeriod = Duration(days: 7);

  // 后台播放状态同步节流：之前 position ~10次/s 全量跨 isolate
  static const Duration playbackSyncMinInterval = Duration(seconds: 1);

  // position state 节流：100ms tick -> 500ms 落 state，秒级 UI 足够
  static const Duration positionStateMinInterval = Duration(milliseconds: 500);

  // 网络重试：弱网/5xx 指数退避
  static const int networkMaxRetries = 2;

  // 下载并发上限
  static const int maxConcurrentDownloads = 2;
}
