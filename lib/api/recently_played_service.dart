import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

class RecentlyPlayedService {
  static const String _key = 'recent_songs';
  static const int _maxSongs = 500;

  Future<void> addSong(Song song) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> songsJson = prefs.getStringList(_key) ?? [];
    
    // Remove if existing (to move to top)
    songsJson.removeWhere((item) {
        try {
            final Map<String, dynamic> map = json.decode(item);
            return map['id'] == song.id;
        } catch (e) {
            return false;
        }
    });

    // Add to top
    songsJson.insert(0, json.encode(song.toJson()));

    // Limit to 500
    if (songsJson.length > _maxSongs) {
      songsJson = songsJson.sublist(0, _maxSongs);
    }

    await prefs.setStringList(_key, songsJson);
  }

  Future<List<Song>> getRecentSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> songsJson = prefs.getStringList(_key) ?? [];
    
    return songsJson.map((item) {
        try {
            return Song.fromManifest(json.decode(item));
        } catch (e) {
            return null;
        }
    }).whereType<Song>().toList();
  }
}
