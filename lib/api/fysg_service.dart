import 'package:dio/dio.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../utils/app_log.dart';
import '../utils/constants.dart';
import '../utils/result.dart';

/// 分页结果：携带 total 后 UI 可用精确 hasMore，不再靠 `length >= size` 猜。
/// 实测 fysg.org 的 /songs、/playlists 均支持 page/size 并返回 data.count。
class PagedList<T> {
  final List<T> items;
  final int total;
  final int page;
  final int size;

  const PagedList({
    required this.items,
    required this.total,
    required this.page,
    required this.size,
  });

  bool get hasMore =>
      total >= 0 ? (page + 1) * size < total : items.length >= size;
}

class FysgService {
  static const String _apiBaseUrl = AppConstants.apiBaseUrl;

  Map<String, String> get _commonQueryParams => {
    '_app': AppConstants.apiAppName,
    '_device': AppConstants.apiDevice,
    '_version': AppConstants.apiVersion,
    '_deviceId': '',
    '_cvr': '0',
  };

  /// 弱网/超时/5xx 指数退避重试；4xx（除 429 外语义明确）直接映射不重试。
  /// dio 统一承担 API + 下载两条链路，不再同时依赖 http。
  Future<Response<dynamic>> _get(
    String path, {
    Map<String, String>? query,
    CancelToken? cancelToken,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt <= AppConstants.networkMaxRetries; attempt++) {
      try {
        final response = await _dio.get<dynamic>(
          path,
          queryParameters: {..._commonQueryParams, ...?query},
          cancelToken: cancelToken,
        );
        final status = response.statusCode ?? 0;
        if (status >= 500) {
          lastError = NetworkError.server(status);
        } else {
          return response;
        }
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) rethrow;
        if (_isRetryable(e)) {
          lastError = e;
        } else {
          final status = e.response?.statusCode;
          if (status != null) _throwForStatus(status, path);
          throw AppError.network('请求失败：${e.message ?? path}');
        }
      } catch (e) {
        lastError = e;
      }
      if (attempt < AppConstants.networkMaxRetries) {
        await Future.delayed(Duration(milliseconds: 400 * (1 << attempt)));
      }
    }
    final err = lastError;
    if (err is NetworkError) throw err;
    if (err is DioException) {
      final status = err.response?.statusCode ?? 0;
      if (status >= 500) throw NetworkError.server(status);
      if (status == 429) throw NetworkError.rateLimited();
      throw NetworkError.timeout('请求超时，请检查网络后重试');
    }
    throw AppError.network('请求超时，请检查网络后重试');
  }

  static bool _isRetryable(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.unknown:
        return true;
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode ?? 0;
        return status >= 500;
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
        return false;
    }
  }

  /// 统一状态码映射：之前仅分 200/>=500/else，401/404/429 全归“请求失败”
  Never _throwForStatus(int statusCode, String action) {
    if (statusCode == 401 || statusCode == 403) {
      throw NetworkError.forbidden(statusCode);
    } else if (statusCode == 404) {
      throw AppError.notFound(action);
    } else if (statusCode == 429) {
      throw NetworkError.rateLimited();
    } else if (statusCode >= 500) {
      throw NetworkError.server(statusCode);
    } else {
      throw AppError.network('请求失败: $statusCode');
    }
  }

  final Map<int, Song> _songDetailsCache = {};
  final Map<int, Future<Song>> _songDetailsInFlight = {};
  final Map<String, _CacheEntry<List<Map<String, dynamic>>>>
  _searchSuggestionsCache = {};
  final Map<String, Future<List<Map<String, dynamic>>>>
  _searchSuggestionsInFlight = {};
  final Map<String, _CacheEntry<PagedList<Song>>> _searchSongsCache = {};
  final Map<String, Future<PagedList<Song>>> _searchSongsInFlight = {};
  final Map<String, _CacheEntry<PagedList<Song>>> _recommendedSongsCache = {};
  final Map<String, Future<PagedList<Song>>> _recommendedSongsInFlight = {};
  final Map<String, _CacheEntry<PagedList<Playlist>>> _collectionCache = {};
  final Map<String, Future<PagedList<Playlist>>> _collectionInFlight = {};
  final Map<String, _CacheEntry<PagedList<Song>>> _collectionSongsCache = {};
  final Map<String, Future<PagedList<Song>>> _collectionSongsInFlight = {};
  final Dio _dio;

  FysgService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _apiBaseUrl,
              connectTimeout: AppConstants.networkTimeout,
              receiveTimeout: AppConstants.networkTimeout,
              headers: AppConstants.defaultHeaders,
              responseType: ResponseType.json,
            ),
          );

  void dispose() {
    _dio.close(force: true);
  }

  // 检查缓存是否新鲜
  bool _isFresh(DateTime timestamp, Duration ttl) {
    return DateTime.now().difference(timestamp) < ttl;
  }

  /// 有界写入：命中时刷新顺序，超限淘汰最旧，防长会话无界增长。
  static void _putBounded<K, V>(Map<K, V> map, K key, V value, int max) {
    map.remove(key);
    map[key] = value;
    while (map.length > max) {
      map.remove(map.keys.first);
    }
  }

  static int _extractCount(Map data) {
    for (final key in ['count', 'total', 'totalCount']) {
      final raw = data[key];
      final n = raw is int ? raw : int.tryParse('$raw');
      if (n != null) return n;
    }
    return -1;
  }

  /// dio 已按 json 解析；兼容 Map / List / 原始字符串三种形态。
  static Map<String, dynamic>? _responseMap(Response<dynamic> response) {
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  static List<Song> _parseSongList(dynamic list) {
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map(
          (item) => Song.fromJson(
            Map<String, dynamic>.from(item),
            assetBase: AppConstants.assetBaseUrl,
          ),
        )
        .toList();
  }

  /// 获取搜索建议
  ///
  /// 返回 Result 类型以便调用方处理错误
  Future<Result<List<Map<String, dynamic>>, AppError>> getSearchSuggestions(
    String query, {
    int size = AppConstants.defaultPageSize,
    CancelToken? cancelToken,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return Result.ok(const []);

    final cacheKey = '${normalized.toLowerCase()}|$size';
    final cached = _searchSuggestionsCache[cacheKey];
    if (cached != null &&
        _isFresh(cached.timestamp, AppConstants.searchCacheTtl)) {
      return Result.ok(List<Map<String, dynamic>>.from(cached.data));
    }

    final inFlight = _searchSuggestionsInFlight[cacheKey];
    if (inFlight != null) {
      try {
        final result = await inFlight;
        return Result.ok(result);
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          return Result.err(NetworkError('已取消', 'cancelled'));
        }
        rethrow;
      }
    }

    final request = _fetchSearchSuggestions(
      normalized,
      size,
      cancelToken: cancelToken,
    );
    _searchSuggestionsInFlight[cacheKey] = request;
    try {
      final result = await request;
      _putBounded(
        _searchSuggestionsCache,
        cacheKey,
        _CacheEntry(timestamp: DateTime.now(), data: result),
        AppConstants.searchCacheMaxEntries,
      );
      return Result.ok(List<Map<String, dynamic>>.from(result));
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        return Result.err(NetworkError('已取消', 'cancelled'));
      }
      return Result.err(AppError.unknown(e));
    } on AppError catch (e) {
      return Result.err(e);
    } catch (e) {
      return Result.err(AppError.unknown(e));
    } finally {
      _searchSuggestionsInFlight.remove(cacheKey);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchSearchSuggestions(
    String query,
    int size, {
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _get(
        '/api/app/songs-random-name',
        query: {'name': query, 'size': size.toString()},
        cancelToken: cancelToken,
      );

      final jsonResponse = _responseMap(response);
      if (jsonResponse == null) return [];
      if (jsonResponse['code'] == 0 && jsonResponse['data'] != null) {
        final data = jsonResponse['data'];
        if (data is List) {
          return data
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        } else if (data is Map && data['list'] != null) {
          return (data['list'] as List)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        }
      }
      return [];
    } on AppError {
      rethrow;
    } catch (e) {
      AppLog.d('Error fetching suggestions: $e');
      throw AppError.network('获取搜索建议失败');
    }
  }

  /// 搜索歌曲（分页版，携带 total；旧方法委托于此保持兼容）
  Future<Result<PagedList<Song>, AppError>> searchSongsPaged(
    String query, {
    int page = AppConstants.defaultPage,
    int size = AppConstants.defaultPageSize,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return Result.ok(
        PagedList(items: const [], total: 0, page: page, size: size),
      );
    }

    final cacheKey = '${normalized.toLowerCase()}|$page|$size';
    final cached = _searchSongsCache[cacheKey];
    if (cached != null &&
        _isFresh(cached.timestamp, AppConstants.searchCacheTtl)) {
      return Result.ok(cached.data);
    }

    final inFlight = _searchSongsInFlight[cacheKey];
    if (inFlight != null) {
      final result = await inFlight;
      return Result.ok(result);
    }

    final request = _fetchSearchSongs(normalized, page, size);
    _searchSongsInFlight[cacheKey] = request;
    try {
      final result = await request;
      _putBounded(
        _searchSongsCache,
        cacheKey,
        _CacheEntry(timestamp: DateTime.now(), data: result),
        AppConstants.searchCacheMaxEntries,
      );
      return Result.ok(result);
    } on AppError catch (e) {
      return Result.err(e);
    } catch (e) {
      return Result.err(AppError.unknown(e));
    } finally {
      _searchSongsInFlight.remove(cacheKey);
    }
  }

  /// 搜索歌曲
  Future<Result<List<Song>, AppError>> searchSongs(
    String query, {
    int page = AppConstants.defaultPage,
    int size = AppConstants.defaultPageSize,
  }) async {
    final result = await searchSongsPaged(query, page: page, size: size);
    return result.when(
      ok: (paged) => Result.ok(List<Song>.from(paged.items)),
      err: (e) => Result.err(e),
    );
  }

  Future<PagedList<Song>> _fetchSearchSongs(
    String query,
    int page,
    int size,
  ) async {
    try {
      final response = await _get(
        '/api/app/songs',
        query: {
          'name': query,
          'page': page.toString(),
          'size': size.toString(),
        },
      );

      final jsonResponse = _responseMap(response);
      if (jsonResponse == null) {
        return PagedList(items: const [], total: -1, page: page, size: size);
      }
      if (jsonResponse['code'] == 0 && jsonResponse['data'] != null) {
        final data = jsonResponse['data'];
        if (data is Map && data['list'] != null) {
          return PagedList(
            items: _parseSongList(data['list']),
            total: _extractCount(data),
            page: page,
            size: size,
          );
        } else if (data is List) {
          return PagedList(
            items: _parseSongList(data),
            total: data.length,
            page: page,
            size: size,
          );
        }
      }
      return PagedList(items: const [], total: -1, page: page, size: size);
    } on AppError {
      rethrow;
    } catch (e) {
      AppLog.d('Error searching songs: $e');
      throw AppError.network('搜索歌曲失败');
    }
  }

  /// 获取推荐歌曲（分页版）
  Future<Result<PagedList<Song>, AppError>> getRecommendedSongsPaged({
    int page = AppConstants.defaultPage,
    int size = AppConstants.defaultPageSize,
  }) async {
    final cacheKey = '$page|$size';
    final cached = _recommendedSongsCache[cacheKey];
    if (cached != null &&
        _isFresh(cached.timestamp, AppConstants.recommendCacheTtl)) {
      return Result.ok(cached.data);
    }

    final inFlight = _recommendedSongsInFlight[cacheKey];
    if (inFlight != null) {
      final result = await inFlight;
      return Result.ok(result);
    }

    final request = _fetchRecommendedSongs(page, size);
    _recommendedSongsInFlight[cacheKey] = request;
    try {
      final result = await request;
      _putBounded(
        _recommendedSongsCache,
        cacheKey,
        _CacheEntry(timestamp: DateTime.now(), data: result),
        AppConstants.recommendCacheMaxEntries,
      );
      return Result.ok(result);
    } on AppError catch (e) {
      return Result.err(e);
    } catch (e) {
      return Result.err(AppError.unknown(e));
    } finally {
      _recommendedSongsInFlight.remove(cacheKey);
    }
  }

  /// 获取推荐歌曲
  Future<Result<List<Song>, AppError>> getRecommendedSongs({
    int page = AppConstants.defaultPage,
    int size = AppConstants.defaultPageSize,
  }) async {
    final result = await getRecommendedSongsPaged(page: page, size: size);
    return result.when(
      ok: (paged) => Result.ok(List<Song>.from(paged.items)),
      err: (e) => Result.err(e),
    );
  }

  Future<PagedList<Song>> _fetchRecommendedSongs(int page, int size) async {
    try {
      // Using "Top Played Monthly" as recommendation
      final response = await _get(
        '/api/app/songs',
        query: {
          'page': page.toString(),
          'size': size.toString(),
          'sort': 'playM',
        },
      );
      final jsonResponse = _responseMap(response);
      if (jsonResponse == null) {
        return PagedList(items: const [], total: -1, page: page, size: size);
      }
      if (jsonResponse['code'] == 0 && jsonResponse['data'] != null) {
        final data = jsonResponse['data'];
        if (data is Map && data['list'] != null) {
          return PagedList(
            items: _parseSongList(data['list']),
            total: _extractCount(data),
            page: page,
            size: size,
          );
        }
      }
      return PagedList(items: const [], total: -1, page: page, size: size);
    } on AppError {
      rethrow;
    } catch (e) {
      AppLog.d('Error fetching recommended songs: $e');
      throw AppError.network('获取推荐歌曲失败');
    }
  }

  /// 获取歌曲详情（详情缓存有界 LRU）
  Future<Result<Song, AppError>> getSongDetails(
    int songId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _songDetailsCache[songId];
      if (cached != null) {
        // 刷新 LRU 顺序
        _songDetailsCache.remove(songId);
        _songDetailsCache[songId] = cached;
        return Result.ok(cached);
      }

      final inFlight = _songDetailsInFlight[songId];
      if (inFlight != null) {
        final result = await inFlight;
        return Result.ok(result);
      }
    }

    final request = _fetchSongDetails(songId);
    if (!forceRefresh) {
      _songDetailsInFlight[songId] = request;
    }

    try {
      final song = await request;
      if (!forceRefresh) {
        _putBounded(
          _songDetailsCache,
          songId,
          song,
          AppConstants.songDetailsCacheMaxEntries,
        );
      }
      return Result.ok(song);
    } on AppError catch (e) {
      return Result.err(e);
    } catch (e) {
      return Result.err(AppError.unknown(e));
    } finally {
      if (!forceRefresh) {
        _songDetailsInFlight.remove(songId);
      }
    }
  }

  Future<Song> _fetchSongDetails(int songId) async {
    try {
      final response = await _get('/api/app/songs/$songId');

      final jsonResponse = _responseMap(response);
      if (jsonResponse == null) {
        throw AppError.cache('无效的歌曲数据格式');
      }
      dynamic songData = jsonResponse;
      if (jsonResponse['data'] != null) {
        songData = jsonResponse['data'];
      }
      if (songData is! Map) {
        throw AppError.cache('无效的歌曲数据格式');
      }

      return Song.fromJson(
        Map<String, dynamic>.from(songData),
        assetBase: AppConstants.assetBaseUrl,
      );
    } on AppError {
      rethrow;
    } catch (e) {
      AppLog.d('Error fetching song details ($songId): $e');
      throw AppError.network('获取歌曲详情失败');
    }
  }

  // --- Playlist / Album APIs ---

  Future<Result<PagedList<Playlist>, AppError>> _fetchCollectionPaged(
    String endpoint, {
    int page = AppConstants.defaultPage,
    int size = AppConstants.defaultPageSize,
    String type = 'playlist',
  }) async {
    final cacheKey = '$endpoint|$type|$page|$size';
    final cached = _collectionCache[cacheKey];
    if (cached != null &&
        _isFresh(cached.timestamp, AppConstants.collectionCacheTtl)) {
      return Result.ok(cached.data);
    }
    final inFlight = _collectionInFlight[cacheKey];
    if (inFlight != null) {
      return Result.ok(await inFlight);
    }
    final request = _doFetchCollection(
      endpoint,
      page: page,
      size: size,
      type: type,
    );
    _collectionInFlight[cacheKey] = request;
    try {
      final result = await request;
      _putBounded(
        _collectionCache,
        cacheKey,
        _CacheEntry(timestamp: DateTime.now(), data: result),
        AppConstants.collectionCacheMaxEntries,
      );
      return Result.ok(result);
    } on AppError catch (e) {
      return Result.err(e);
    } catch (e) {
      AppLog.d('Error fetching collection $endpoint: $e');
      return Result.err(AppError.unknown(e));
    } finally {
      _collectionInFlight.remove(cacheKey);
    }
  }

  Future<PagedList<Playlist>> _doFetchCollection(
    String endpoint, {
    int page = AppConstants.defaultPage,
    int size = AppConstants.defaultPageSize,
    String type = 'playlist',
  }) async {
    try {
      final response = await _get(
        '/api/app/$endpoint',
        query: {'page': page.toString(), 'size': size.toString()},
      );

      final jsonResponse = _responseMap(response);
      if (jsonResponse == null) {
        return PagedList(items: const [], total: -1, page: page, size: size);
      }
      if (jsonResponse['code'] == 0 && jsonResponse['data'] != null) {
        final data = jsonResponse['data'];
        if (data is Map && data['list'] != null) {
          final items = (data['list'] as List)
              .whereType<Map>()
              .map((item) {
                return Playlist.fromJson(
                  Map<String, dynamic>.from(item),
                  type,
                );
              })
              .toList();
          return PagedList(
            items: items,
            total: _extractCount(data),
            page: page,
            size: size,
          );
        }
      }
      return PagedList(items: const [], total: -1, page: page, size: size);
    } on AppError {
      rethrow;
    } catch (e) {
      AppLog.d('Error fetching collection $endpoint: $e');
      throw AppError.unknown(e);
    }
  }

  Future<Result<List<Playlist>, AppError>> _fetchCollection(
    String endpoint, {
    int page = AppConstants.defaultPage,
    int size = AppConstants.defaultPageSize,
    String type = 'playlist',
  }) async {
    final result = await _fetchCollectionPaged(
      endpoint,
      page: page,
      size: size,
      type: type,
    );
    return result.when(
      ok: (paged) => Result.ok(List<Playlist>.from(paged.items)),
      err: (e) => Result.err(e),
    );
  }

  Future<Result<List<Playlist>, AppError>> getPlaylists({
    int page = AppConstants.defaultPage,
    int size = AppConstants.defaultPageSize,
  }) async {
    return _fetchCollection(
      'playlists',
      page: page,
      size: size,
      type: 'playlist',
    );
  }

  Future<Result<List<Playlist>, AppError>> getAlbums({
    int page = AppConstants.defaultPage,
    int size = AppConstants.defaultPageSize,
  }) async {
    return _fetchCollection('albums', page: page, size: size, type: 'album');
  }

  Future<Result<PagedList<Playlist>, AppError>> getPlaylistsPaged({
    int page = AppConstants.defaultPage,
    int size = AppConstants.defaultPageSize,
  }) async {
    return _fetchCollectionPaged(
      'playlists',
      page: page,
      size: size,
      type: 'playlist',
    );
  }

  Future<Result<PagedList<Playlist>, AppError>> getAlbumsPaged({
    int page = AppConstants.defaultPage,
    int size = AppConstants.defaultPageSize,
  }) async {
    return _fetchCollectionPaged(
      'albums',
      page: page,
      size: size,
      type: 'album',
    );
  }

  Future<Result<PagedList<Song>, AppError>> getCollectionSongsPaged(
    String type,
    int id, {
    int page = AppConstants.defaultPage,
    int size = AppConstants.defaultPageSize,
  }) async {
    String paramKey;

    if (type == 'album') {
      paramKey = 'album';
    } else if (type == 'playlist') {
      paramKey = 'playlist';
    } else {
      return Result.ok(
        PagedList(items: const [], total: 0, page: page, size: size),
      );
    }

    final cacheKey = '$type|$id|$page|$size';
    final cached = _collectionSongsCache[cacheKey];
    if (cached != null &&
        _isFresh(cached.timestamp, AppConstants.collectionCacheTtl)) {
      return Result.ok(cached.data);
    }
    final inFlight = _collectionSongsInFlight[cacheKey];
    if (inFlight != null) {
      return Result.ok(await inFlight);
    }
    final request = _doFetchCollectionSongs(
      paramKey,
      '$id',
      page: page,
      size: size,
    );
    _collectionSongsInFlight[cacheKey] = request;
    try {
      final paged = await request;
      _putBounded(
        _collectionSongsCache,
        cacheKey,
        _CacheEntry(timestamp: DateTime.now(), data: paged),
        AppConstants.collectionCacheMaxEntries,
      );
      return Result.ok(paged);
    } on AppError catch (e) {
      return Result.err(e);
    } catch (e) {
      AppLog.d('Error fetching collection songs ($type:$id): $e');
      return Result.err(AppError.unknown(e));
    } finally {
      _collectionSongsInFlight.remove(cacheKey);
    }
  }

  Future<PagedList<Song>> _doFetchCollectionSongs(
    String paramKey,
    String paramValue, {
    int page = AppConstants.defaultPage,
    int size = AppConstants.defaultPageSize,
  }) async {
    try {
      final response = await _get(
        '/api/app/songs',
        query: {
          paramKey: paramValue,
          'page': page.toString(),
          'size': size.toString(),
        },
      );
      final jsonResponse = _responseMap(response);
      if (jsonResponse == null) {
        return PagedList(items: const [], total: -1, page: page, size: size);
      }
      if (jsonResponse['code'] == 0 && jsonResponse['data'] != null) {
        final data = jsonResponse['data'];
        if (data is Map && data['list'] != null) {
          return PagedList(
            items: _parseSongList(data['list']),
            total: _extractCount(data),
            page: page,
            size: size,
          );
        }
      }
      return PagedList(items: const [], total: -1, page: page, size: size);
    } on AppError {
      rethrow;
    } catch (e) {
      AppLog.d('Error fetching collection songs: $e');
      throw AppError.unknown(e);
    }
  }

  Future<Result<List<Song>, AppError>> getCollectionSongs(
    String type,
    int id, {
    int page = AppConstants.defaultPage,
    int size = AppConstants.defaultPageSize,
  }) async {
    final result = await getCollectionSongsPaged(
      type,
      id,
      page: page,
      size: size,
    );
    return result.when(
      ok: (paged) => Result.ok(List<Song>.from(paged.items)),
      err: (e) => Result.err(e),
    );
  }
}

/// 缓存条目包装类
class _CacheEntry<T> {
  final DateTime timestamp;
  final T data;

  const _CacheEntry({required this.timestamp, required this.data});
}
