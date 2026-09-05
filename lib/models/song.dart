import '../utils/constants.dart';

class Song {
  final int id;
  final String name;
  final String? artist;
  final String? album;
  final String? cover; // URL to cover image
  final String? url; // URL to audio file
  final String? lyrics; // LRC content

  Song({
    required this.id,
    required this.name,
    this.artist,
    this.album,
    this.cover,
    this.url,
    this.lyrics,
  });

  factory Song.fromJson(
    Map<String, dynamic> json, {
    String assetBase = AppConstants.assetBaseUrl,
  }) {
    // FYSG API structure adaptation (defensive: dirty data must not crash)
    String? artistName;
    try {
      final authors = json['authors'];
      if (authors is List && authors.isNotEmpty) {
        final first = authors[0];
        if (first is Map && first['name'] != null) {
          artistName = '${first['name']}';
        }
      } else if (json['author'] is Map) {
        final author = json['author'] as Map;
        if (author['name'] != null) artistName = '${author['name']}';
      } else if (json['artist'] != null) {
        artistName = '${json['artist']}';
      }
    } catch (_) {
      artistName = null;
    }

    String? albumName;
    String? coverUrl;
    try {
      final album = json['album'];
      if (album is Map) {
        if (album['name'] != null) albumName = '${album['name']}';
        if (album['cover'] != null) coverUrl = '${album['cover']}';
      } else if (json['cover'] != null) {
        coverUrl = '${json['cover']}';
      }
    } catch (_) {
      // keep nulls
    }

    // Fix cover URL if it's relative
    if (coverUrl != null && !coverUrl.startsWith('http')) {
      coverUrl = '$assetBase$coverUrl';
    }

    String? audioUrl;
    try {
      final rawUrl = json['url'];
      if (rawUrl != null) audioUrl = '$rawUrl';
    } catch (_) {
      audioUrl = null;
    }
    if (audioUrl != null && !audioUrl.startsWith('http')) {
      // Browser analysis shows audio files reside in /song_high/ directory
      // relative to the asset base. Images do not.
      if (!audioUrl.startsWith('/song_high') &&
          !audioUrl.startsWith('song_high')) {
        audioUrl = '$assetBase/song_high$audioUrl';
      } else {
        audioUrl = '$assetBase$audioUrl';
      }
    }

    final int songId = int.tryParse('${json['songId'] ?? 0}') ?? 0;
    final int fallbackId =
        int.tryParse('${json['id'] ?? json['audioId'] ?? 0}') ?? 0;
    final int parsedId = songId != 0 ? songId : fallbackId;

    final rawName = json['name'];
    final name = rawName == null ? '' : '$rawName';

    return Song(
      id: parsedId,
      // artist 为空时由 UI 层用 l10n.unknownArtist 兜底，不在此硬编码英文
      name: name,
      artist: (artistName == null || artistName.isEmpty) ? null : artistName,
      album: albumName,
      cover: coverUrl,
      url: audioUrl,
      lyrics: json['lyrics'],
    );
  }

  factory Song.fromManifest(Map<String, dynamic> json) {
    try {
      final idRaw = json['id'];
      final id = idRaw is int ? idRaw : int.tryParse('$idRaw') ?? 0;
      final nameRaw = json['name'];
      return Song(
        id: id,
        name: nameRaw == null ? '' : '$nameRaw',
        artist: json['artist'] == null ? null : '${json['artist']}',
        album: json['album'] == null ? null : '${json['album']}',
        cover: json['cover'] == null ? null : '${json['cover']}',
        url: json['url'] == null ? null : '${json['url']}',
        lyrics: json['lyrics'] == null ? null : '${json['lyrics']}',
      );
    } catch (_) {
      return Song(id: 0, name: '');
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'artist': artist,
      'album': album,
      'cover': cover,
      'url': url,
      'lyrics': lyrics,
    };
  }
}
