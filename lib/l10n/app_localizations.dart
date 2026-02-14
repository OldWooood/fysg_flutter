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
      'search_hint': 'Search songs, artists...',
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
      'search_hint': '搜索歌曲、专辑、歌手...',
      'categories': '全部分类',
      'albums': '专辑',
      'playlists': '精选歌单',
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
    },
  };

  String get home => _localizedValues[locale.languageCode]!['home']!;
  String get browse => _localizedValues[locale.languageCode]!['browse']!;
  String get search => _localizedValues[locale.languageCode]!['search']!;
  String get mine => _localizedValues[locale.languageCode]!['mine']!;
  String get appTitle => _localizedValues[locale.languageCode]!['app_title']!;
  String get recommended => _localizedValues[locale.languageCode]!['recommended']!;
  String get recentlyPlayed => _localizedValues[locale.languageCode]!['recently_played']!;
  String get seeAll => _localizedValues[locale.languageCode]!['see_all']!;
  String get history => _localizedValues[locale.languageCode]!['history']!;
  String get downloaded => _localizedValues[locale.languageCode]!['downloaded']!;
  String get playAll => _localizedValues[locale.languageCode]!['play_all']!;
  String get noHistory => _localizedValues[locale.languageCode]!['no_history']!;
  String get noDownloads => _localizedValues[locale.languageCode]!['no_downloads']!;
  String get noLyrics => _localizedValues[locale.languageCode]!['no_lyrics']!;
  String get searchHint => _localizedValues[locale.languageCode]!['search_hint']!;
  String get categories => _localizedValues[locale.languageCode]!['categories']!;
  String get albums => _localizedValues[locale.languageCode]!['albums']!;
  String get playlists => _localizedValues[locale.languageCode]!['playlists']!;
  String get authors => _localizedValues[locale.languageCode]!['authors']!;
  String get books => _localizedValues[locale.languageCode]!['books']!;
  String get songTab => _localizedValues[locale.languageCode]!['song_tab']!;
  String get lyricsTab => _localizedValues[locale.languageCode]!['lyrics_tab']!;
  String get searchAction => _localizedValues[locale.languageCode]!['search_action']!;
  String get noResults => _localizedValues[locale.languageCode]!['no_results']!;
  String get searchHistory => _localizedValues[locale.languageCode]!['search_history']!;
  String get clearHistory => _localizedValues[locale.languageCode]!['clear_history']!;
  String get downloadStarted => _localizedValues[locale.languageCode]!['download_started']!;
  String get alreadyDownloaded => _localizedValues[locale.languageCode]!['already_downloaded']!;
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'zh'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) => SynchronousFuture<AppLocalizations>(AppLocalizations(locale));

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
