import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const _localizedValues = {
    'en': {
      'home': 'Home',
      'browse': 'Browse',
      'search': 'Search',
      'mine': 'Mine',
      'app_title': 'Gospel Songs',
      'recommended': 'Recommended',
      'recently_played': 'Recently Played',
      'see_all': 'See All',
      'history': 'History',
      'downloaded': 'Downloaded',
      'play_all': 'Play All',
      'no_history': 'No history yet',
      'no_downloads': 'No downloads yet',
      'no_lyrics': 'No Lyrics Available',
      'search_hint': 'Search songs',
      'categories': 'Categories',
      'albums': 'Albums',
      'playlists': 'Playlists',
      'authors': 'Authors',
      'books': 'Books',
      'song_tab': 'Song',
      'lyrics_tab': 'Lyrics',
      'search_action': 'Search',
      'no_results': 'No results found',
      'search_history': 'Search History',
      'clear_history': 'Clear History',
      'download_started': 'Download started',
      'already_downloaded': 'Already downloaded',
      'loop': 'Loop',
      'download': 'Download',
      'playlist': 'Playlist',
      'loop_order': 'Order',
      'loop_shuffle': 'Shuffle',
      'loop_single': 'Loop One',
      'favorites': 'Playlist Favorites',
      'favorite_playlist': 'Favorite Playlist',
      'favorited': 'Favorited',
      'add_favorite': 'Add to Favorites',
      'remove_favorite': 'Remove Favorite',
      'no_favorites': 'No favorites yet',
      'retry': 'Retry',
      'load_failed': 'Failed to load',
      'unknown': 'Unknown',
      'unknown_artist': 'Unknown Artist',
      'search_empty_hint': 'Search songs, albums or artists',
      'share': 'Share',
      'speed': 'Speed',
      'share_text_song': 'Recommended a gospel song: ',
      'play': 'Play',
      'pause': 'Pause',
    },
    'zh': {
      'home': '首页',
      'browse': '发现',
      'search': '搜索',
      'mine': '我的',
      'app_title': '福音诗歌',
      'recommended': '每日推荐',
      'recently_played': '最近播放',
      'see_all': '查看全部',
      'history': '播放历史',
      'downloaded': '已下载',
      'play_all': '全部播放',
      'no_history': '暂无播放记录',
      'no_downloads': '暂无下载内容',
      'no_lyrics': '暂无歌词',
      'search_hint': '搜索歌曲',
      'categories': '全部分类',
      'albums': '专辑',
      'playlists': '歌单',
      'authors': '歌手',
      'books': '诗歌本',
      'song_tab': '音乐',
      'lyrics_tab': '歌词',
      'search_action': '搜索',
      'no_results': '未找到相关结果',
      'search_history': '搜索历史',
      'clear_history': '清空记录',
      'download_started': '开始下载',
      'already_downloaded': '文件已存在',
      'loop': '循环',
      'download': '下载',
      'playlist': '列表',
      'loop_order': '顺序',
      'loop_shuffle': '随机',
      'loop_single': '单曲',
      'favorites': '歌单收藏',
      'favorite_playlist': '收藏歌单',
      'favorited': '已收藏',
      'add_favorite': '收藏',
      'remove_favorite': '取消收藏',
      'no_favorites': '暂无收藏',
      'retry': '重试',
      'load_failed': '加载失败',
      'unknown': '未知',
      'unknown_artist': '未知歌手',
      'search_empty_hint': '搜索歌曲、专辑或歌手',
      'share': '分享',
      'speed': '倍速',
      'share_text_song': '推荐一首福音诗歌：',
      'play': '播放',
      'pause': '暂停',
    },
  };

  static String _get(Locale locale, String key) {
    // 未知语言回退到英文，避免 `!` 强解崩溃（如 zh_Hant / ja 等系统语言）
    final table =
        _localizedValues[locale.languageCode] ?? _localizedValues['en']!;
    return table[key] ?? _localizedValues['en']![key] ?? key;
  }

  String get home => _get(locale, 'home');
  String get browse => _get(locale, 'browse');
  String get search => _get(locale, 'search');
  String get mine => _get(locale, 'mine');
  String get appTitle => _get(locale, 'app_title');
  String get recommended => _get(locale, 'recommended');
  String get recentlyPlayed => _get(locale, 'recently_played');
  String get seeAll => _get(locale, 'see_all');
  String get history => _get(locale, 'history');
  String get downloaded => _get(locale, 'downloaded');
  String get playAll => _get(locale, 'play_all');
  String get noHistory => _get(locale, 'no_history');
  String get noDownloads => _get(locale, 'no_downloads');
  String get noLyrics => _get(locale, 'no_lyrics');
  String get searchHint => _get(locale, 'search_hint');
  String get categories => _get(locale, 'categories');
  String get albums => _get(locale, 'albums');
  String get playlists => _get(locale, 'playlists');
  String get authors => _get(locale, 'authors');
  String get books => _get(locale, 'books');
  String get songTab => _get(locale, 'song_tab');
  String get lyricsTab => _get(locale, 'lyrics_tab');
  String get searchAction => _get(locale, 'search_action');
  String get noResults => _get(locale, 'no_results');
  String get searchHistory => _get(locale, 'search_history');
  String get clearHistory => _get(locale, 'clear_history');
  String get downloadStarted => _get(locale, 'download_started');
  String get alreadyDownloaded => _get(locale, 'already_downloaded');
  String get loop => _get(locale, 'loop');
  String get download => _get(locale, 'download');
  String get playlist => _get(locale, 'playlist');
  String get loopOrder => _get(locale, 'loop_order');
  String get loopShuffle => _get(locale, 'loop_shuffle');
  String get loopSingle => _get(locale, 'loop_single');
  String get favorites => _get(locale, 'favorites');
  String get favoritePlaylist => _get(locale, 'favorite_playlist');
  String get favorited => _get(locale, 'favorited');
  String get addFavorite => _get(locale, 'add_favorite');
  String get removeFavorite => _get(locale, 'remove_favorite');
  String get noFavorites => _get(locale, 'no_favorites');
  String get retry => _get(locale, 'retry');
  String get loadFailed => _get(locale, 'load_failed');
  String get unknown => _get(locale, 'unknown');
  String get unknownArtist => _get(locale, 'unknown_artist');
  String get searchEmptyHint => _get(locale, 'search_empty_hint');
  String get share => _get(locale, 'share');
  String get speed => _get(locale, 'speed');
  String get play => _get(locale, 'play');
  String get pause => _get(locale, 'pause');
  String shareTextSong(String song) => '${_get(locale, 'share_text_song')}$song';
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'zh'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizations(locale));

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
