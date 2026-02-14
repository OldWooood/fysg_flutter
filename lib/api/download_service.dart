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

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> getLocalFile(int songId) async {
    final path = await _localPath;
    return File('$path/songs/$songId.mp3');
  }

  Future<void> downloadSong(Song song, {Function(int, int)? onProgress}) async {
    if (song.url == null) return;
    
    final file = await getLocalFile(song.id);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }

    await _dio.download(
      song.url!,
      file.path,
      onReceiveProgress: onProgress,
      options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            'Referer': 'https://www.fysg.org/',
          }
      ),
    );

    // Save to manifest
    await _saveToManifest(song);
  }

  Future<void> _saveToManifest(Song song) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> downloaded = prefs.getStringList(_downloadKey) ?? [];
    
    // Check if already in list
    bool exists = false;
    for (var s in downloaded) {
        final map = json.decode(s);
        if (map['id'] == song.id) {
            exists = true;
            break;
        }
    }

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
    for (var s in downloaded) {
        final map = json.decode(s);
        final song = Song.fromManifest(map);
        final file = await getLocalFile(song.id);
        if (file.existsSync()) {
            songs.add(song);
            validFiles.add(s);
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
      downloaded.removeWhere((s) => json.decode(s)['id'] == songId);
      await prefs.setStringList(_downloadKey, downloaded);
  }
}
