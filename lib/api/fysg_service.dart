import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import '../models/playlist.dart';

class FysgService {
  static const String _baseUrl = 'https://www.fysg.org';
  static const String _apiBase = '$_baseUrl/api/app';
  static const String _assetBase = 'https://sg-file.nanqiao.xyz';
  static const String _commonParams = '_app=fuyinshige&_device=web&_version=5.1.7&_deviceId=&_cvr=0';
  static final Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Referer': 'https://www.fysg.org/',
    'Origin': 'https://www.fysg.org',
  };

  Future<List<Map<String, dynamic>>> getSearchSuggestions(String query, {int size = 10}) async {
    if (query.trim().isEmpty) return [];
    
    final queryParams = {
      'name': query,
      'size': size.toString(),
      '_app': 'fuyinshige',
      '_device': 'web',
      '_version': '5.1.7',
      '_deviceId': '',
      '_cvr': '0',
    };

    final uri = Uri.https('www.fysg.org', '/api/app/songs-random-name', queryParams);

    try {
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
        if (jsonResponse['code'] == 0 && jsonResponse['data'] != null) {
          final data = jsonResponse['data'];
          if (data is List) {
            return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
          } else if (data is Map && data['list'] != null) {
            return (data['list'] as List).map((item) => Map<String, dynamic>.from(item as Map)).toList();
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching suggestions: $e');
    }
    return [];
  }

  Future<List<Song>> searchSongs(String query, {int page = 0, int size = 20}) async {
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
      final response = await http.get(uri, headers: _headers);
      
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
        if (jsonResponse['code'] == 0 && jsonResponse['data'] != null) {
            final data = jsonResponse['data'];
            if (data is Map && data['list'] != null) {
               return (data['list'] as List).map((item) => Song.fromJson(item, assetBase: _assetBase)).toList();
            } else if (data is List) {
               return data.map((item) => Song.fromJson(item, assetBase: _assetBase)).toList();
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
      // Using "Top Played Monthly" as recommendation
    final response = await http.get(
        Uri.parse('$_apiBase/songs?page=$page&size=$size&sort=playM&$_commonParams'),
        headers: _headers,
    );
    
    if (response.statusCode == 200) {
      final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
      if (jsonResponse['code'] == 0 && jsonResponse['data'] != null) {
          final data = jsonResponse['data'];
          if (data['list'] != null) {
             return (data['list'] as List).map((item) => Song.fromJson(item, assetBase: _assetBase)).toList();
          }
      }
    }
    return [];
  }

  Future<Song> getSongDetails(int songId) async {
    final response = await http.get(
        Uri.parse('$_apiBase/songs/$songId?$_commonParams'),
        headers: _headers,
    );
    
    if (response.statusCode == 200) {
      final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
      // Detail response might be direct object or wrapped. Usually wrapped in 'data' based on search structure.
      // Let's assume consistent wrapper { code: 0, data: { ... } }
      dynamic songData = jsonResponse;
      if (jsonResponse['data'] != null) {
          songData = jsonResponse['data'];
      }
      
      return Song.fromJson(songData, assetBase: _assetBase);
    }
    throw Exception('Failed to load song details');
  }

  // Helper to fetch audio URL if not present in details (Keeping for safety, though likely not needed with assetBase fix)
  Future<String?> getAudioUrl(int songId) async {
      // implementation kept same, but less likely to be used now
      return null; 
  }

  // --- Playlist / Album / Book / Author APIs ---

  Future<List<Playlist>> _fetchCollection(String endpoint, {int page = 0, int size = 20, String type = 'playlist'}) async {
    final response = await http.get(
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
    return _fetchCollection('playlists', page: page, size: size, type: 'playlist');
  }

  Future<List<Playlist>> getAlbums({int page = 0, int size = 20}) async {
    return _fetchCollection('albums', page: page, size: size, type: 'album');
  }

  Future<List<Playlist>> getBooks({int page = 0, int size = 20}) async {
    return _fetchCollection('books', page: page, size: size, type: 'book');
  }

  Future<List<Playlist>> getAuthors({int page = 0, int size = 20}) async {
    return _fetchCollection('authors', page: page, size: size, type: 'author');
  }

  Future<List<Song>> getCollectionSongs(String type, int id, {int page = 0, int size = 20}) async {
    String endpoint = 'songs';
    String param = '';
    
    if (type == 'album') param = 'album=$id';
    else if (type == 'playlist') param = 'playlist=$id';
    else if (type == 'author') param = 'author=$id';
    else if (type == 'book') {
        endpoint = 'bookSongs';
        param = 'book=$id';
    }

    final response = await http.get(
      Uri.parse('$_apiBase/$endpoint?$param&page=$page&size=$size&$_commonParams'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
       if (jsonResponse['code'] == 0 && jsonResponse['data'] != null) {
          final data = jsonResponse['data'];
          if (data['list'] != null) {
             return (data['list'] as List).map((item) => Song.fromJson(item, assetBase: _assetBase)).toList();
          }
       }
    }
    return [];
  }
}
