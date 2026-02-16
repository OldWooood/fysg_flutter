import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import 'dart:convert';

final downloadServiceProvider = Provider((ref) => DownloadService());

class DownloadService {
  final Dio _dio = Dio();
  static const String _downloadKey = 'downloaded_songs';
  static const Map<String, String> _downloadHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Referer': 'https://www.fysg.org/',
  };

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<String> get _prefetchPath async {
    final directory = await getTemporaryDirectory();
    return directory.path;
  }

  Future<File> getLocalFile(int songId) async {
    final path = await _localPath;
    return File('$path/songs/$songId.mp3');
  }

  Future<File> getPrefetchFile(int songId) async {
    final path = await _prefetchPath;
    return File('$path/prefetch/$songId.mp3');
  }

  Future<bool> isPrefetched(int songId) async {
    final file = await getPrefetchFile(songId);
    return file.existsSync();
  }

  Future<void> deletePrefetch(int songId) async {
    final file = await getPrefetchFile(songId);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  Future<void> prefetchSong(Song song, {Function(int, int)? onProgress}) async {
    if (song.url == null) return;

    final file = await getPrefetchFile(song.id);
    if (file.existsSync()) return;
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }

    await _downloadToFile(song.url!, file.path, onProgress: onProgress);
  }

  Future<void> downloadSong(Song song, {Function(int, int)? onProgress}) async {
    if (song.url == null) return;

    final file = await getLocalFile(song.id);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }

    await _downloadToFile(song.url!, file.path, onProgress: onProgress);

    // Save to manifest
    await _saveToManifest(song);
  }

  Future<void> _downloadToFile(
    String url,
    String path, {
    Function(int, int)? onProgress,
  }) async {
    await _dio.download(
      url,
      path,
      onReceiveProgress: onProgress,
      options: Options(headers: _downloadHeaders),
    );
  }

  Future<void> _saveToManifest(Song song) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> downloaded = prefs.getStringList(_downloadKey) ?? [];

    final exists = downloaded.any((item) {
      final map = json.decode(item) as Map<String, dynamic>;
      return map['id'] == song.id;
    });

    if (!exists) {
      downloaded.add(json.encode(song.toJson()));
      await prefs.setStringList(_downloadKey, downloaded);
    }
  }

  Future<List<Song>> getDownloadedSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> downloaded = prefs.getStringList(_downloadKey) ?? [];

    List<Song> songs = [];
    List<String> validFiles = [];

    // Verify files still exist
    for (final item in downloaded) {
      final map = json.decode(item) as Map<String, dynamic>;
      final song = Song.fromManifest(map);
      final file = await getLocalFile(song.id);
      if (file.existsSync()) {
        songs.add(song);
        validFiles.add(item);
      }
    }

    if (validFiles.length != downloaded.length) {
      await prefs.setStringList(_downloadKey, validFiles);
    }

    return songs;
  }

  Future<bool> isDownloaded(int songId) async {
    final file = await getLocalFile(songId);
    return file.existsSync();
  }

  Future<void> deleteDownload(int songId) async {
    final file = await getLocalFile(songId);
    if (file.existsSync()) {
      file.deleteSync();
    }

    final prefs = await SharedPreferences.getInstance();
    final List<String> downloaded = prefs.getStringList(_downloadKey) ?? [];
    downloaded.removeWhere((item) {
      final map = json.decode(item) as Map<String, dynamic>;
      return map['id'] == songId;
    });
    await prefs.setStringList(_downloadKey, downloaded);
  }
}
