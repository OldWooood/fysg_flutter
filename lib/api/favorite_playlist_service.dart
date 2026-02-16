import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist.dart';

final favoritePlaylistServiceProvider = Provider(
  (ref) => FavoritePlaylistService(),
);

final favoritePlaylistsProvider = FutureProvider.autoDispose<List<Playlist>>((
  ref,
) async {
  return ref.read(favoritePlaylistServiceProvider).getFavorites();
});

class FavoritePlaylistService {
  static const String _favoritesKey = 'favorite_playlists';

  Future<List<Playlist>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_favoritesKey) ?? [];
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
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_favoritesKey) ?? [];
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

    await prefs.setStringList(_favoritesKey, existing.values.toList());
  }
}
