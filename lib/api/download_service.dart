import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import 'dart:convert';

final downloadServiceProvider = Provider((ref) {
  final service = DownloadService();
  ref.onDispose(service.dispose);
  return service;
});

class DownloadService {
  final Dio _dio = Dio();
  static const String _downloadKey = 'downloaded_songs';
  static const String _prefetchIndexKey = 'prefetch_song_ids';
  static const int _prefetchMaxBytes = 4 * 1024 * 1024 * 1024;
  static const Map<String, String> _downloadHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Referer': 'https://www.fysg.org/',
  };

  void dispose() {
    _dio.close(force: true);
  }

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<String> get _prefetchPath async {
    final directory = await getTemporaryDirectory();
    return directory.path;
  }

  Future<Directory> _getPrefetchDir() async {
    final path = await _prefetchPath;
    return Directory('$path/prefetch');
  }

  Future<File> getLocalFile(int songId) async {
    final path = await _localPath;
    return File('$path/songs/$songId.mp3');
  }

  Future<File> getPrefetchFile(int songId) async {
    final path = await _prefetchPath;
    return File('$path/prefetch/$songId.mp3');
  }

  Future<File> getPrefetchTempFile(int songId) async {
    final path = await _prefetchPath;
    return File('$path/prefetch/$songId.part');
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
    final tempFile = await getPrefetchTempFile(songId);
    if (tempFile.existsSync()) {
      tempFile.deleteSync();
    }
    await _removePrefetchIndex(songId);
  }

  Future<void> prefetchSong(Song song, {Function(int, int)? onProgress}) async {
    if (song.url == null) return;

    final finalFile = await getPrefetchFile(song.id);
    if (finalFile.existsSync()) return;
    if (!finalFile.parent.existsSync()) {
      finalFile.parent.createSync(recursive: true);
    }

    final tempFile = await getPrefetchTempFile(song.id);
    if (tempFile.existsSync()) {
      tempFile.deleteSync();
    }

    try {
      await _downloadToFile(song.url!, tempFile.path, onProgress: onProgress);
      if (finalFile.existsSync()) {
        finalFile.deleteSync();
      }
      await tempFile.rename(finalFile.path);
      await _addPrefetchIndex(song.id);
      await enforcePrefetchLimit();
    } catch (_) {
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
      rethrow;
    }
  }

  Future<void> enforcePrefetchLimit({int maxBytes = _prefetchMaxBytes}) async {
    final dir = await _getPrefetchDir();
    if (!dir.existsSync()) return;

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
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefetchIndexKey) ?? [];
    return raw.map(int.tryParse).whereType<int>().toSet();
  }

  Future<void> _addPrefetchIndex(int songId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefetchIndexKey) ?? [];
    final exists = raw.any((id) => id == songId.toString());
    if (exists) return;
    raw.add(songId.toString());
    await prefs.setStringList(_prefetchIndexKey, raw);
  }

  Future<void> _removePrefetchIndex(int songId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefetchIndexKey) ?? [];
    raw.removeWhere((id) => id == songId.toString());
    await prefs.setStringList(_prefetchIndexKey, raw);
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
