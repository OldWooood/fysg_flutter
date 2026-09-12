import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../utils/constants.dart';

class ImageCacheService {
  ImageCacheService._();

  static final Map<String, String> headers = {
    ...AppConstants.defaultHeaders,
    'Sec-Fetch-Dest': 'image',
    'Sec-Fetch-Mode': 'no-cors',
    'Sec-Fetch-Site': 'cross-site',
  };

  static CacheManager? _cacheManager;

  /// 全局图片磁盘缓存：200 个 / 7 天，避免长列表无限膨胀。
  static CacheManager get cacheManager =>
      _cacheManager ??= CacheManager(
        Config(
          'fysgImageCache',
          maxNrOfCacheObjects: AppConstants.imageCacheMaxObjects,
          stalePeriod: AppConstants.imageCacheStalePeriod,
        ),
      );
}
