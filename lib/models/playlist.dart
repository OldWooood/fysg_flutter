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
    String assetBase = 'https://www.fysg.org',
  }) {
    String? coverUrl = json['cover'];
    if (coverUrl != null && !coverUrl.startsWith('http')) {
      // Books usually have covers in /gepu/ which might need assetBase or might be relative
      coverUrl = '$assetBase$coverUrl';
    }

    // Adapt to different ID fields if necessary, but usually it's just 'id'
    int id = json['id'] is int
        ? json['id']
        : int.tryParse(json['id'].toString()) ?? 0;

    return Playlist(
      id: id,
      name: json['name'] ?? 'Unknown',
      cover: coverUrl,
      count: json['playCount'] ?? json['count'], // normalize count
      type: type,
    );
  }

  factory Playlist.fromManifest(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'],
      name: json['name'],
      cover: json['cover'],
      count: json['count'],
      type: json['type'],
    );
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
