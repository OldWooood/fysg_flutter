import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import '../models/playlist.dart';

class FysgService {
  static const String _baseUrl = 'https://www.fysg.org';
  static const String _apiBase = '$_baseUrl/api/app';
  static const String _assetBase = 'https://sg-file.nanqiao.xyz';
  static const String _commonParams =
      '_app=fuyinshige&_device=web&_version=5.1.7&_deviceId=&_cvr=0';
  static final Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Referer': 'https://www.fysg.org/',
    'Origin': 'https://www.fysg.org',
  };
  static const Duration _searchCacheTtl = Duration(seconds: 45);
  static const Duration _recommendCacheTtl = Duration(minutes: 2);
  final Map<int, Song> _songDetailsCache = {};
  final Map<int, Future<Song>> _songDetailsInFlight = {};
  final Map<String, ({DateTime timestamp, List<Map<String, dynamic>> data})>
  _searchSuggestionsCache = {};
  final Map<String, Future<List<Map<String, dynamic>>>>
  _searchSuggestionsInFlight = {};
  final Map<String, ({DateTime timestamp, List<Song> data})> _searchSongsCache =
      {};
  final Map<String, Future<List<Song>>> _searchSongsInFlight = {};
  final Map<String, ({DateTime timestamp, List<Song> data})>
  _recommendedSongsCache = {};
  final Map<String, Future<List<Song>>> _recommendedSongsInFlight = {};
  final http.Client _client;

  FysgService({http.Client? client}) : _client = client ?? http.Client();

  Future<List<Map<String, dynamic>>> getSearchSuggestions(
    String query, {
    int size = 10,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return [];
    final cacheKey = '${normalized.toLowerCase()}|$size';
    final cached = _searchSuggestionsCache[cacheKey];
    if (cached != null && _isFresh(cached.timestamp, _searchCacheTtl)) {
      return List<Map<String, dynamic>>.from(cached.data);
    }
    final inFlight = _searchSuggestionsInFlight[cacheKey];
    if (inFlight != null) return inFlight;

    final request = _fetchSearchSuggestions(normalized, size);
    _searchSuggestionsInFlight[cacheKey] = request;
    try {
      final result = await request;
      _searchSuggestionsCache[cacheKey] = (
        timestamp: DateTime.now(),
        data: result,
      );
      return List<Map<String, dynamic>>.from(result);
    } finally {
      _searchSuggestionsInFlight.remove(cacheKey);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchSearchSuggestions(
    String query,
    int size,
  ) async {
    final queryParams = {
      'name': query,
      'size': size.toString(),
      '_app': 'fuyinshige',
      '_device': 'web',
      '_version': '5.1.7',
      '_deviceId': '',
      '_cvr': '0',
    };

    final uri = Uri.https(
      'www.fysg.org',
      '/api/app/songs-random-name',
      queryParams,
    );

    try {
      final response = await _client.get(uri, headers: _headers);

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
      }
    } catch (e) {
      debugPrint('Error fetching suggestions: $e');
    }
    return [];
  }

  Future<List<Song>> searchSongs(
    String query, {
    int page = 0,
    int size = 20,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return [];
    final cacheKey = '${normalized.toLowerCase()}|$page|$size';
    final cached = _searchSongsCache[cacheKey];
    if (cached != null && _isFresh(cached.timestamp, _searchCacheTtl)) {
      return List<Song>.from(cached.data);
    }
    final inFlight = _searchSongsInFlight[cacheKey];
    if (inFlight != null) return inFlight;

    final request = _fetchSearchSongs(normalized, page, size);
    _searchSongsInFlight[cacheKey] = request;
    try {
      final result = await request;
      _searchSongsCache[cacheKey] = (timestamp: DateTime.now(), data: result);
      return List<Song>.from(result);
    } finally {
      _searchSongsInFlight.remove(cacheKey);
    }
  }

  Future<List<Song>> _fetchSearchSongs(String query, int page, int size) async {
    final queryParams = {
      'name': query,
      'page': page.toString(),
      'size': size.toString(),
      '_app': 'fuyinshige',
      '_device': 'web',
      '_version': '5.1.7',
      '_deviceId': '',
      '_cvr': '0',
    };

    final uri = Uri.https('www.fysg.org', '/api/app/songs', queryParams);

    try {
      final response = await _client.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
        if (jsonResponse['code'] == 0 && jsonResponse['data'] != null) {
          final data = jsonResponse['data'];
          if (data is Map && data['list'] != null) {
            return (data['list'] as List)
                .map((item) => Song.fromJson(item, assetBase: _assetBase))
                .toList();
          } else if (data is List) {
            return data
                .map((item) => Song.fromJson(item, assetBase: _assetBase))
                .toList();
          }
        }
      }
    } catch (e) {
      debugPrint('Error searching songs: $e');
    }
    return [];
  }

  // New method for Home Page Recommendations
  Future<List<Song>> getRecommendedSongs({int page = 0, int size = 20}) async {
    final cacheKey = '$page|$size';
    final cached = _recommendedSongsCache[cacheKey];
    if (cached != null && _isFresh(cached.timestamp, _recommendCacheTtl)) {
      return List<Song>.from(cached.data);
    }
    final inFlight = _recommendedSongsInFlight[cacheKey];
    if (inFlight != null) return inFlight;

    final request = _fetchRecommendedSongs(page, size);
    _recommendedSongsInFlight[cacheKey] = request;
    try {
      final result = await request;
      _recommendedSongsCache[cacheKey] = (
        timestamp: DateTime.now(),
        data: result,
      );
      return List<Song>.from(result);
    } finally {
      _recommendedSongsInFlight.remove(cacheKey);
    }
  }

  Future<List<Song>> _fetchRecommendedSongs(int page, int size) async {
    // Using "Top Played Monthly" as recommendation
    final response = await _client.get(
      Uri.parse(
        '$_apiBase/songs?page=$page&size=$size&sort=playM&$_commonParams',
      ),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
      if (jsonResponse['code'] == 0 && jsonResponse['data'] != null) {
        final data = jsonResponse['data'];
        if (data['list'] != null) {
          return (data['list'] as List)
              .map((item) => Song.fromJson(item, assetBase: _assetBase))
              .toList();
        }
      }
    }
    return [];
  }

  bool _isFresh(DateTime timestamp, Duration ttl) {
    return DateTime.now().difference(timestamp) < ttl;
  }

  Future<Song> getSongDetails(int songId, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _songDetailsCache[songId];
      if (cached != null) return cached;

      final inFlight = _songDetailsInFlight[songId];
      if (inFlight != null) return inFlight;
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
      return song;
    } finally {
      if (!forceRefresh) {
        _songDetailsInFlight.remove(songId);
      }
    }
  }

  Future<Song> _fetchSongDetails(int songId) async {
    final response = await _client.get(
      Uri.parse('$_apiBase/songs/$songId?$_commonParams'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load song details');
    }

    final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
    dynamic songData = jsonResponse;
    if (jsonResponse is Map && jsonResponse['data'] != null) {
      songData = jsonResponse['data'];
    }
    if (songData is! Map) {
      throw Exception('Invalid song details payload');
    }

    return Song.fromJson(
      Map<String, dynamic>.from(songData),
      assetBase: _assetBase,
    );
  }

  // Helper to fetch audio URL if not present in details (Keeping for safety, though likely not needed with assetBase fix)
  Future<String?> getAudioUrl(int songId) async {
    // implementation kept same, but less likely to be used now
    return null;
  }

  // --- Playlist / Album APIs ---

  Future<List<Playlist>> _fetchCollection(
    String endpoint, {
    int page = 0,
    int size = 20,
    String type = 'playlist',
  }) async {
    final response = await _client.get(
      Uri.parse('$_apiBase/$endpoint?page=$page&size=$size&$_commonParams'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
      if (jsonResponse['code'] == 0 && jsonResponse['data'] != null) {
        final data = jsonResponse['data'];
        if (data['list'] != null) {
          return (data['list'] as List).map((item) {
            // Determine type based on endpoint if generic
            String finalType = type;
            // If fetching authors, type is 'author', etc.
            return Playlist.fromJson(item, finalType);
          }).toList();
        }
      }
    }
    return [];
  }

  Future<List<Playlist>> getPlaylists({int page = 0, int size = 20}) async {
    return _fetchCollection(
      'playlists',
      page: page,
      size: size,
      type: 'playlist',
    );
  }

  Future<List<Playlist>> getAlbums({int page = 0, int size = 20}) async {
    return _fetchCollection('albums', page: page, size: size, type: 'album');
  }

  Future<List<Song>> getCollectionSongs(
    String type,
    int id, {
    int page = 0,
    int size = 20,
  }) async {
    String endpoint = 'songs';
    String param = '';

    if (type == 'album') {
      param = 'album=$id';
    } else if (type == 'playlist') {
      param = 'playlist=$id';
    } else {
      return [];
    }

    final response = await _client.get(
      Uri.parse(
        '$_apiBase/$endpoint?$param&page=$page&size=$size&$_commonParams',
      ),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
      if (jsonResponse['code'] == 0 && jsonResponse['data'] != null) {
        final data = jsonResponse['data'];
        if (data['list'] != null) {
          return (data['list'] as List)
              .map((item) => Song.fromJson(item, assetBase: _assetBase))
              .toList();
        }
      }
    }
    return [];
  }
}
