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
    String assetBase = 'https://www.fysg.org',
  }) {
    // FYSG API structure adaptation

    String? artistName;
    if (json['authors'] != null && (json['authors'] as List).isNotEmpty) {
      artistName = json['authors'][0]['name'];
    } else if (json['author'] != null) {
      // sometimes it's direct object
      artistName = json['author']['name'];
    }

    String? albumName;
    String? coverUrl;
    if (json['album'] != null) {
      albumName = json['album']['name'];
      coverUrl = json['album']['cover'];
    }

    // Fix cover URL if it's relative
    if (coverUrl != null && !coverUrl.startsWith('http')) {
      coverUrl = '$assetBase$coverUrl';
    }

    String? audioUrl = json['url'];
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
        int.tryParse('${json['id'] ?? json['audioId'] ?? 0}') ??
        0;
    final int parsedId = songId != 0 ? songId : fallbackId;

    return Song(
      id: parsedId,
      name: json['name'] ?? 'Unknown Title',
      artist: artistName ?? 'Unknown Artist',
      album: albumName,
      cover: coverUrl,
      url: audioUrl,
      lyrics: json['lyrics'],
    );
  }

  factory Song.fromManifest(Map<String, dynamic> json) {
    return Song(
      id: json['id'],
      name: json['name'],
      artist: json['artist'],
      album: json['album'],
      cover: json['cover'],
      url: json['url'],
      lyrics: json['lyrics'],
    );
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
