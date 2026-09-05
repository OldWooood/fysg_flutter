import '../models/song.dart';

/// 从 `PlayerNotifier` 抽出的歌曲合并/判等纯函数，便于单测.
///
/// 之前这些逻辑与播放状态耦合在 922 行上帝类里，现为无状态工具。
class SongResolver {
  const SongResolver();

  Song mergeSong(Song base, Song details) {
    final detailsLyrics = details.lyrics;
    return Song(
      id: base.id,
      name: details.name.isNotEmpty ? details.name : base.name,
      artist: (details.artist == null || details.artist!.isEmpty)
          ? base.artist
          : details.artist,
      album: details.album ?? base.album,
      cover: details.cover ?? base.cover,
      url: details.url ?? base.url,
      lyrics: (detailsLyrics != null && detailsLyrics.isNotEmpty)
          ? detailsLyrics
          : base.lyrics,
    );
  }

  bool isSameSong(Song a, Song b) {
    return a.id == b.id &&
        a.name == b.name &&
        a.artist == b.artist &&
        a.album == b.album &&
        a.cover == b.cover &&
        a.url == b.url &&
        a.lyrics == b.lyrics;
  }
}
