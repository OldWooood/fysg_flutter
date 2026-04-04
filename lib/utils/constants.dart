/// 应用常量配置
class AppConstants {
  AppConstants._();

  // API 相关
  static const String apiBaseUrl = 'https://www.fysg.org';
  static const String assetBaseUrl = 'https://sg-file.nanqiao.xyz';
  static const String apiVersion = '5.1.7';
  static const String apiAppName = 'fuyinshige';
  static const String apiDevice = 'web';

  // 默认请求头
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
  static const int prefetchMaxBytes = 4 * 1024 * 1024; // 4GB

  // UI 相关
  static const double loadMoreTriggerExtent = 600.0;
  static const double miniPlayerHeight = 80.0;
  static const Duration scrollDebounceMs = Duration(milliseconds: 120);
  static const Duration searchDebounceMs = Duration(milliseconds: 300);
}
