import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import '../providers/shared_preferences_provider.dart';
import '../utils/constants.dart';

final recentlyPlayedServiceProvider = Provider((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return RecentlyPlayedService(prefs);
});

final recentSongsProvider = FutureProvider<List<Song>>((ref) async {
  return ref.watch(recentlyPlayedServiceProvider).getRecentSongs();
});

class RecentlyPlayedService {
  static const int _maxSongs = 500;
  final SharedPreferences _prefs;

  RecentlyPlayedService(this._prefs);

  Future<void> addSong(Song song) async {
    List<String> songsJson =
        _prefs.getStringList(AppConstants.spRecentSongs) ?? [];

    // Remove if existing (to move to top)
    songsJson.removeWhere((item) {
      try {
        final map = json.decode(item) as Map<String, dynamic>;
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

    await _prefs.setStringList(AppConstants.spRecentSongs, songsJson);
  }

  Future<List<Song>> getRecentSongs() async {
    final List<String> songsJson =
        _prefs.getStringList(AppConstants.spRecentSongs) ?? [];

    return songsJson
        .map((item) {
          try {
            final map = json.decode(item) as Map<String, dynamic>;
            return Song.fromManifest(map);
          } catch (e) {
            return null;
          }
        })
        .whereType<Song>()
        .toList();
  }
}
