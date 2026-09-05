import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/playlist.dart';
import '../models/song.dart';
import '../utils/constants.dart';
import '../utils/result.dart';

class FysgService {
  static final Uri _apiBaseUri = Uri.parse(AppConstants.apiBaseUrl);

  Map<String, String> get _commonQueryParams => {
    '_app': AppConstants.apiAppName,
    '_device': AppConstants.apiDevice,
    '_version': AppConstants.apiVersion,
    '_deviceId': '',
    '_cvr': '0',
  };

  Uri _buildUri(String path, [Map<String, String>? extra]) {
    return Uri.https(_apiBaseUri.host, path, {
      ..._commonQueryParams,
      ...?extra,
    });
  }

  Future<http.Response> _get(Uri uri) {
    return _client
        .get(uri, headers: AppConstants.defaultHeaders)
        .timeout(
          AppConstants.networkTimeout,
          onTimeout: () => throw AppError.network('请求超时，请检查网络后重试'),
        );
  }

  /// 统一状态码映射：之前仅分 200/>=500/else，401/404/429 全归“请求失败”
  Never _throwForStatus(int statusCode, String action) {
    if (statusCode == 401 || statusCode == 403) {
      throw AppError.network('访问被拒绝($statusCode)，请稍后重试');
    } else if (statusCode == 404) {
      throw AppError.notFound(action);
    } else if (statusCode == 429) {
      throw AppError.network('请求过于频繁，请稍后重试');
    } else if (statusCode >= 500) {
      throw AppError.network('服务器错误: $statusCode');
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
  final Map<String, _CacheEntry<List<Song>>> _searchSongsCache = {};
  final Map<String, Future<List<Song>>> _searchSongsInFlight = {};
  final Map<String, _CacheEntry<List<Song>>> _recommendedSongsCache = {};
  final Map<String, Future<List<Song>>> _recommendedSongsInFlight = {};
  final http.Client _client;

  FysgService({http.Client? client}) : _client = client ?? http.Client();

  void dispose() {
    _client.close();
  }

  // 检查缓存是否新鲜
  bool _isFresh(DateTime timestamp, Duration ttl) {
    return DateTime.now().difference(timestamp) < ttl;
  }

  /// 获取搜索建议
  ///
  /// 返回 Result 类型以便调用方处理错误
  Future<Result<List<Map<String, dynamic>>, AppError>> getSearchSuggestions(
    String query, {
    int size = AppConstants.defaultPageSize,
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
      final result = await inFlight;
      return Result.ok(result);
    }

    final request = _fetchSearchSuggestions(normalized, size);
    _searchSuggestionsInFlight[cacheKey] = request;
    try {
      final result = await request;
      _searchSuggestionsCache[cacheKey] = _CacheEntry(
        timestamp: DateTime.now(),
        data: result,
      );
      return Result.ok(List<Map<String, dynamic>>.from(result));
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
    int size,
  ) async {
    final uri = _buildUri('/api/app/songs-random-name', {
      'name': query,
      'size': size.toString(),
    });

    try {
      final response = await _get(uri);

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
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
      } else {
        _throwForStatus(response.statusCode, '搜索建议');
      }
    } on AppError {
      rethrow;
    } catch (e) {
      debugPrint('Error fetching suggestions: $e');
      throw AppError.network('获取搜索建议失败');
    }
  }

  /// 搜索歌曲
  Future<Result<List<Song>, AppError>> searchSongs(
    String query, {
    int page = AppConstants.defaultPage,
    int size = AppConstants.defaultPageSize,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return Result.ok(const []);

    final cacheKey = '${normalized.toLowerCase()}|$page|$size';
    final cached = _searchSongsCache[cacheKey];
    if (cached != null &&
        _isFresh(cached.timestamp, AppConstants.searchCacheTtl)) {
      return Result.ok(List<Song>.from(cached.data));
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
      _searchSongsCache[cacheKey] = _CacheEntry(
        timestamp: DateTime.now(),
        data: result,
      );
      return Result.ok(List<Song>.from(result));
    } on AppError catch (e) {
      return Result.err(e);
    } catch (e) {
      return Result.err(AppError.unknown(e));
    } finally {
      _searchSongsInFlight.remove(cacheKey);
    }
  }

  Future<List<Song>> _fetchSearchSongs(String query, int page, int size) async {
    final uri = _buildUri('/api/app/songs', {
      'name': query,
      'page': page.toString(),
      'size': size.toString(),
    });

    try {
      final response = await _get(uri);

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
        if (jsonResponse['code'] == 0 && jsonResponse['data'] != null) {
          final data = jsonResponse['data'];
          if (data is Map && data['list'] != null) {
            return (data['list'] as List)
                .map(
                  (item) =>
                      Song.fromJson(item, assetBase: AppConstants.assetBaseUrl),
                )
                .toList();
          } else if (data is List) {
            return data
                .map(
                  (item) =>
                      Song.fromJson(item, assetBase: AppConstants.assetBaseUrl),
                )
                .toList();
          }
        }
        return [];
      } else {
        _throwForStatus(response.statusCode, '搜索歌曲');
      }
    } on AppError {
      rethrow;
    } catch (e) {
      debugPrint('Error searching songs: $e');
      throw AppError.network('搜索歌曲失败');
    }
  }

  /// 获取推荐歌曲
  Future<Result<List<Song>, AppError>> getRecommendedSongs({
    int page = AppConstants.defaultPage,
    int size = AppConstants.defaultPageSize,
  }) async {
    final cacheKey = '$page|$size';
    final cached = _recommendedSongsCache[cacheKey];
    if (cached != null &&
        _isFresh(cached.timestamp, AppConstants.recommendCacheTtl)) {
      return Result.ok(List<Song>.from(cached.data));
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
      _recommendedSongsCache[cacheKey] = _CacheEntry(
        timestamp: DateTime.now(),
        data: result,
      );
      return Result.ok(List<Song>.from(result));
    } on AppError catch (e) {
      return Result.err(e);
    } catch (e) {
      return Result.err(AppError.unknown(e));
    } finally {
      _recommendedSongsInFlight.remove(cacheKey);
    }
  }

  Future<List<Song>> _fetchRecommendedSongs(int page, int size) async {
    try {
      // Using "Top Played Monthly" as recommendation
      final uri = _buildUri('/api/app/songs', {
        'page': page.toString(),
        'size': size.toString(),
        'sort': 'playM',
      });
      final response = await _get(uri);

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
        if (jsonResponse['code'] == 0 && jsonResponse['data'] != null) {
          final data = jsonResponse['data'];
          if (data['list'] != null) {
            return (data['list'] as List)
                .map(
                  (item) =>
                      Song.fromJson(item, assetBase: AppConstants.assetBaseUrl),
                )
                .toList();
          }
        }
        return [];
      } else {
        _throwForStatus(response.statusCode, '推荐歌曲');
      }
    } on AppError {
      rethrow;
    } catch (e) {
      debugPrint('Error fetching recommended songs: $e');
      throw AppError.network('获取推荐歌曲失败');
    }
  }

  /// 获取歌曲详情
  Future<Result<Song, AppError>> getSongDetails(
    int songId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _songDetailsCache[songId];
      if (cached != null) return Result.ok(cached);

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
        _songDetailsCache[songId] = song;
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
      final uri = _buildUri('/api/app/songs/$songId');
      final response = await _get(uri);

      if (response.statusCode == 404) {
        throw AppError.notFound('歌曲 $songId');
      }
      if (response.statusCode != 200) {
        _throwForStatus(response.statusCode, '歌曲详情');
      }

      final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
      dynamic songData = jsonResponse;
      if (jsonResponse is Map && jsonResponse['data'] != null) {
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
      debugPrint('Error fetching song details ($songId): $e');
      throw AppError.network('获取歌曲详情失败');
    }
  }

  // --- Playlist / Album APIs ---

  Future<Result<List<Playlist>, AppError>> _fetchCollection(
    String endpoint, {
    int page = AppConstants.defaultPage,
    int size = AppConstants.defaultPageSize,
    String type = 'playlist',
  }) async {
    try {
      final uri = _buildUri('/api/app/$endpoint', {
        'page': page.toString(),
        'size': size.toString(),
      });
      final response = await _get(uri);

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
        if (jsonResponse['code'] == 0 && jsonResponse['data'] != null) {
          final data = jsonResponse['data'];
          if (data['list'] != null) {
            return Result.ok(
              (data['list'] as List).map((item) {
                return Playlist.fromJson(item, type);
              }).toList(),
            );
          }
        }
        return Result.ok(const []);
      } else {
        _throwForStatus(response.statusCode, endpoint);
      }
    } on AppError catch (e) {
      return Result.err(e);
    } catch (e) {
      debugPrint('Error fetching collection $endpoint: $e');
      return Result.err(AppError.unknown(e));
    }
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

  Future<Result<List<Song>, AppError>> getCollectionSongs(
    String type,
    int id, {
    int page = AppConstants.defaultPage,
    int size = AppConstants.defaultPageSize,
  }) async {
    String paramKey;
    String paramValue = '$id';

    if (type == 'album') {
      paramKey = 'album';
    } else if (type == 'playlist') {
      paramKey = 'playlist';
    } else {
      return Result.ok(const []);
    }

    try {
      final uri = _buildUri('/api/app/songs', {
        paramKey: paramValue,
        'page': page.toString(),
        'size': size.toString(),
      });
      final response = await _get(uri);

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
        if (jsonResponse['code'] == 0 && jsonResponse['data'] != null) {
          final data = jsonResponse['data'];
          if (data['list'] != null) {
            return Result.ok(
              (data['list'] as List)
                  .map(
                    (item) => Song.fromJson(
                      item,
                      assetBase: AppConstants.assetBaseUrl,
                    ),
                  )
                  .toList(),
            );
          }
        }
        return Result.ok(const []);
      } else {
        _throwForStatus(response.statusCode, '歌单歌曲');
      }
    } on AppError catch (e) {
      return Result.err(e);
    } catch (e) {
      debugPrint('Error fetching collection songs ($type:$id): $e');
      return Result.err(AppError.unknown(e));
    }
  }
}

/// 缓存条目包装类
class _CacheEntry<T> {
  final DateTime timestamp;
  final T data;

  const _CacheEntry({required this.timestamp, required this.data});
}
