import '../utils/constants.dart';

class Playlist {
  final int id;
  final String name;
  final String? cover;
  final int? count; // Song count or play count depending on context
  final String type; // 'album', 'playlist'

  Playlist({
    required this.id,
    required this.name,
    this.cover,
    this.count,
    required this.type,
  });

  factory Playlist.fromJson(
    Map<String, dynamic> json,
    String type, {
    String assetBase = AppConstants.assetBaseUrl,
  }) {
    String? coverUrl;
    try {
      final rawCover = json['cover'];
      if (rawCover != null) {
        coverUrl = '$rawCover';
        if (!coverUrl.startsWith('http')) {
          // Books usually have covers in /gepu/ which might need assetBase or might be relative
          coverUrl = '$assetBase$coverUrl';
        }
      }
    } catch (_) {
      coverUrl = null;
    }

    // Adapt to different ID fields if necessary, but usually it's just 'id'
    int id = 0;
    try {
      final rawId = json['id'];
      id = rawId is int ? rawId : int.tryParse('$rawId') ?? 0;
    } catch (_) {
      id = 0;
    }

    int? count;
    try {
      final rawCount = json['playCount'] ?? json['count'];
      if (rawCount is int) {
        count = rawCount;
      } else if (rawCount != null) {
        count = int.tryParse('$rawCount');
      }
    } catch (_) {
      count = null;
    }

    final rawName = json['name'];
    return Playlist(
      id: id,
      name: rawName == null ? '' : '$rawName',
      cover: coverUrl,
      count: count, // normalize count
      type: type,
    );
  }

  factory Playlist.fromManifest(Map<String, dynamic> json) {
    try {
      final rawId = json['id'];
      final id = rawId is int ? rawId : int.tryParse('$rawId') ?? 0;
      final rawName = json['name'];
      final rawCount = json['count'];
      return Playlist(
        id: id,
        name: rawName == null ? '' : '$rawName',
        cover: json['cover'] == null ? null : '${json['cover']}',
        count: rawCount is int ? rawCount : int.tryParse('$rawCount'),
        type: json['type'] == null ? 'playlist' : '${json['type']}',
      );
    } catch (_) {
      return Playlist(id: 0, name: '', type: 'playlist');
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'cover': cover,
      'count': count,
      'type': type,
    };
  }
}
