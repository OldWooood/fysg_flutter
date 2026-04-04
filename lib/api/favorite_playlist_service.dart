import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist.dart';
import '../providers/shared_preferences_provider.dart';
import '../utils/constants.dart';

final favoritePlaylistServiceProvider = Provider(
  (ref) => FavoritePlaylistService(ref.watch(sharedPreferencesProvider)),
);

final favoritePlaylistsProvider = FutureProvider.autoDispose<List<Playlist>>(
  (ref) async {
    return ref.read(favoritePlaylistServiceProvider).getFavorites();
  },
);

class FavoritePlaylistService {
  final SharedPreferences _prefs;

  FavoritePlaylistService(this._prefs);

  Future<List<Playlist>> getFavorites() async {
    final raw = _prefs.getStringList(AppConstants.spFavoritePlaylists) ?? [];
    final result = <Playlist>[];
    for (final item in raw) {
      try {
        final map = json.decode(item) as Map<String, dynamic>;
        result.add(Playlist.fromManifest(map));
      } catch (_) {
        // skip bad entries
      }
    }
    return result;
  }

  Future<bool> isFavorite(Playlist playlist) async {
    final list = await getFavorites();
    return list.any((p) => p.id == playlist.id && p.type == playlist.type);
  }

  Future<void> toggleFavorite(Playlist playlist) async {
    final raw = _prefs.getStringList(AppConstants.spFavoritePlaylists) ?? [];
    final key = '${playlist.type}:${playlist.id}';
    final existing = <String, String>{};

    for (final item in raw) {
      try {
        final map = json.decode(item) as Map<String, dynamic>;
        final id = map['id'];
        final type = map['type'];
        if (id == null || type == null) continue;
        existing['$type:$id'] = item;
      } catch (_) {
        // skip bad entries
      }
    }

    if (existing.containsKey(key)) {
      existing.remove(key);
    } else {
      existing[key] = json.encode(playlist.toJson());
    }

    await _prefs.setStringList(
      AppConstants.spFavoritePlaylists,
      existing.values.toList(),
    );
  }
}
