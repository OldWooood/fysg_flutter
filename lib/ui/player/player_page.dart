import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../api/image_cache_service.dart';
import '../../l10n/app_localizations.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../utils/lyrics.dart';
import '../../utils/toast_utils.dart';
import '../common/song_cover.dart';
import 'playlist_bottom_sheet.dart';

/// 歌词解析缓存
/// 使用 Provider 缓存解析结果，避免每次 rebuild 都重新解析
final _lyricsCacheProvider = Provider.family<List<LyricLine>, String?>(
  (ref, lyrics) => parseLyrics(lyrics),
);

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _lyricsTabActive = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WakelockPlus.enable();
    _tabController.addListener(_onTabChanged);
    // 打开播放页时补齐当前歌曲详情（歌词等）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final song = ref.read(playerProvider.select((s) => s.currentSong));
      if (song != null) {
        ref.read(playerProvider.notifier).ensureSongDetailsLoaded(song.id);
      }
    });
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() => _lyricsTabActive = _tabController.index == 1);
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    final lyrics = ref.watch(_lyricsCacheProvider(song?.lyrics));

    if (song == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: Colors.white,
            size: 30,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
      ),
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        // 下拉手势关闭播放页（歌词列表滚动时由其自行接管手势）
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity > 600 && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
        child: Stack(
          children: [
            Positioned.fill(child: _PlayerBackground(coverUrl: song.cover)),
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _CoverView(song: song),
                        _LyricsView(lyrics: lyrics, active: _lyricsTabActive),
                      ],
                    ),
                  ),
                  _ControlsSection(tabController: _tabController),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 封面视图：仅在歌曲变化时重建
class _CoverView extends StatelessWidget {
  final Song song;

  const _CoverView({required this.song});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        // Keep enough room for title/artist so cover never squeezes text out.
        final imageSize = (availableHeight * 0.46).clamp(160.0, 240.0);
        final topSpacing = (availableHeight * 0.08).clamp(8.0, 24.0);
        final middleSpacing = (availableHeight * 0.04).clamp(10.0, 18.0);
        final titleFontSize = (availableHeight * 0.055).clamp(22.0, 30.0);

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: topSpacing),
                  Container(
                    height: imageSize,
                    width: imageSize,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 20,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SongCover(
                        imageUrl: song.cover,
                        fit: BoxFit.cover,
                        placeholderIcon: Icons.album,
                        placeholderIconSize: 56,
                      ),
                    ),
                  ),
                  SizedBox(height: middleSpacing),
                  Text(
                    song.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    song.artist ?? AppLocalizations.of(context).unknownArtist,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 封面主色渐变背景，替代高斯模糊以降低 GPU 开销
class _PlayerBackground extends StatefulWidget {
  final String? coverUrl;

  const _PlayerBackground({required this.coverUrl});

  @override
  State<_PlayerBackground> createState() => _PlayerBackgroundState();
}

class _PlayerBackgroundState extends State<_PlayerBackground> {
  static final _paletteCache = <String, Color>{};
  static const _fallbackColor = Color(0xFF20242E);
  Color _dominantColor = _fallbackColor;

  @override
  void initState() {
    super.initState();
    _extractPalette();
  }

  @override
  void didUpdateWidget(covariant _PlayerBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverUrl != widget.coverUrl) {
      _dominantColor = _paletteCache[widget.coverUrl] ?? _fallbackColor;
      _extractPalette();
    }
  }

  Future<void> _extractPalette() async {
    final url = widget.coverUrl;
    if (url == null) {
      if (mounted) setState(() => _dominantColor = _fallbackColor);
      return;
    }
    final cached = _paletteCache[url];
    if (cached != null) {
      if (mounted) setState(() => _dominantColor = cached);
      return;
    }
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(url, headers: ImageCacheService.headers),
        maximumColorCount: 16,
      );
      final color =
          palette.vibrantColor?.color ??
          palette.mutedColor?.color ??
          palette.dominantColor?.color;
      if (color != null && mounted) {
        _paletteCache[url] = color;
        setState(() => _dominantColor = color);
      }
    } catch (_) {
      // 取色失败保持默认背景
    }
  }

  @override
  Widget build(BuildContext context) {
    final topColor = Color.lerp(_dominantColor, Colors.black, 0.35)!;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topColor, Colors.black],
        ),
      ),
    );
  }
}

/// 歌词视图：只订阅 position，避免整页重建
class _LyricsView extends ConsumerStatefulWidget {
  final List<LyricLine> lyrics;
  final bool active;

  const _LyricsView({required this.lyrics, required this.active});

  @override
  ConsumerState<_LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<_LyricsView> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  bool _userScrolling = false;
  Timer? _scrollTimer;
  int _lastScrolledIndex = -1;

  @override
  void didUpdateWidget(covariant _LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _userScrolling) return;
        final position = ref.read(playerProvider.select((s) => s.position));
        final index = findCurrentLyricIndex(widget.lyrics, position);
        if (index >= 0) _scrollToCurrentLine(index);
      });
    }
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    super.dispose();
  }

  void _scrollToCurrentLine(int index) {
    if (_userScrolling || index < 0 || index == _lastScrolledIndex) return;
    if (!_itemScrollController.isAttached) return;

    _lastScrolledIndex = index;
    _itemScrollController.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.5, // Center the item
    );
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(playerProvider.select((s) => s.position));

    if (widget.lyrics.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).noLyrics,
          style: const TextStyle(color: Colors.white),
        ),
      );
    }

    final currentIndex = findCurrentLyricIndex(widget.lyrics, position);
    if (currentIndex != -1 && widget.active) {
      _scrollToCurrentLine(currentIndex);
    }

    return GestureDetector(
      onTapDown: (_) {
        _userScrolling = true;
        _scrollTimer?.cancel();
      },
      onTapUp: (_) {
        _scrollTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) _userScrolling = false;
        });
      },
      child: ScrollablePositionedList.builder(
        itemScrollController: _itemScrollController,
        itemPositionsListener: _itemPositionsListener,
        itemCount: widget.lyrics.length,
        // Increased top padding to avoid overlap with AppBar/TabBar
        padding: EdgeInsets.fromLTRB(
          20,
          kToolbarHeight + 20,
          20,
          MediaQuery.paddingOf(context).bottom + 40,
        ),
        itemBuilder: (context, index) {
          final isCurrent = index == currentIndex;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                widget.lyrics[index].text,
                style: TextStyle(
                  color: isCurrent ? Colors.white : Colors.white38,
                  fontSize: isCurrent ? 24 : 18,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 控制区：TabBar / 进度条 / 播放按钮 / 功能按钮
class _ControlsSection extends ConsumerWidget {
  final TabController tabController;

  const _ControlsSection({required this.tabController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final mode = ref.watch(playerProvider.select((s) => s.mode));
    final speed = ref.watch(playerProvider.select((s) => s.speed));
    final song = ref.watch(playerProvider.select((s) => s.currentSong));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // TabBar moved here
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: TabBar(
            controller: tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            dividerColor: Colors.transparent,
            tabs: [
              Tab(text: AppLocalizations.of(context).songTab),
              Tab(text: AppLocalizations.of(context).lyricsTab),
            ],
          ),
        ),
        _Seekbar(),
        _buildTransportControls(context, ref, isPlaying),
        const SizedBox(height: 20),
        _buildOptionButtons(context, ref, song, mode, speed),
      ],
    );
  }

  Widget _buildTransportControls(
    BuildContext context,
    WidgetRef ref,
    bool isPlaying,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: MaterialLocalizations.of(context).previousPageTooltip,
          icon: const Icon(Icons.skip_previous, color: Colors.white, size: 40),
          onPressed: () => ref.read(playerProvider.notifier).previous(),
        ),
        Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          child: IconButton(
            tooltip: isPlaying
                ? AppLocalizations.of(context).pause
                : AppLocalizations.of(context).play,
            icon: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.black,
              size: 40,
            ),
            onPressed: () =>
                ref.read(playerProvider.notifier).togglePlayPause(),
          ),
        ),
        IconButton(
          tooltip: MaterialLocalizations.of(context).nextPageTooltip,
          icon: const Icon(Icons.skip_next, color: Colors.white, size: 40),
          onPressed: () => ref.read(playerProvider.notifier).next(),
        ),
      ],
    );
  }

  Future<void> _downloadCurrent(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(playerProvider.notifier)
        .downloadCurrentSong();
    if (result == null || !context.mounted) return;

    final message = result == DownloadResult.started
        ? AppLocalizations.of(context).downloadStarted
        : AppLocalizations.of(context).alreadyDownloaded;

    ToastUtils.showToast(context, message);
  }

  Future<void> _shareSong(BuildContext context, Song? song) async {
    if (song == null) return;
    final l10n = AppLocalizations.of(context);
    final buffer = StringBuffer(
      l10n.shareTextSong('${song.name} - ${song.artist ?? ''}'),
    );
    final url = song.url;
    if (url != null && url.isNotEmpty) buffer.writeln(url);
    try {
      await SharePlus.instance.share(ShareParams(text: buffer.toString()));
    } catch (_) {
      // 用户取消分享或分享失败，忽略
    }
  }

  static const _speedOptions = [1.0, 1.25, 1.5, 0.75];

  void _cycleSpeed(WidgetRef ref, double current) {
    final index = _speedOptions.indexOf(current);
    final next = _speedOptions[(index + 1) % _speedOptions.length];
    ref.read(playerProvider.notifier).setSpeed(next);
  }

  Widget _buildOptionButtons(
    BuildContext context,
    WidgetRef ref,
    Song? song,
    PlaybackMode mode,
    double speed,
  ) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildOptionButton(
            context,
            icon: _getModeIcon(mode),
            label: _getModeLabel(mode, context),
            onPressed: () => ref.read(playerProvider.notifier).toggleMode(),
          ),
          _buildOptionButton(
            context,
            icon: Icons.speed,
            label: '${l10n.speed} ${_formatSpeed(speed)}x',
            onPressed: () => _cycleSpeed(ref, speed),
          ),
          _buildOptionButton(
            context,
            icon: Icons.download_outlined,
            label: l10n.download,
            onPressed: () => _downloadCurrent(context, ref),
          ),
          _buildOptionButton(
            context,
            icon: Icons.share_outlined,
            label: l10n.share,
            onPressed: () => _shareSong(context, song),
          ),
          _buildOptionButton(
            context,
            icon: Icons.playlist_play,
            label: l10n.playlist,
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const PlaylistBottomSheet(),
              );
            },
          ),
        ],
      ),
    );
  }

  static String _formatSpeed(double speed) =>
      speed == speed.roundToDouble() ? speed.toStringAsFixed(0) : '$speed';

  IconData _getModeIcon(PlaybackMode mode) {
    return switch (mode) {
      PlaybackMode.sequence => Icons.repeat,
      PlaybackMode.shuffle => Icons.shuffle,
      PlaybackMode.single => Icons.repeat_one,
    };
  }

  String _getModeLabel(PlaybackMode mode, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (mode) {
      PlaybackMode.sequence => l10n.loopOrder,
      PlaybackMode.shuffle => l10n.loopShuffle,
      PlaybackMode.single => l10n.loopSingle,
    };
  }

  Widget _buildOptionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 26),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 进度条与时间标签：唯一订阅 position 的位置，拖动期间不被播放进度打断
class _Seekbar extends ConsumerStatefulWidget {
  const _Seekbar();

  @override
  ConsumerState<_Seekbar> createState() => _SeekbarState();
}

class _SeekbarState extends ConsumerState<_Seekbar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final duration = ref.watch(playerProvider.select((s) => s.duration));
    final position = ref.watch(playerProvider.select((s) => s.position));

    final maxSeconds = duration.inSeconds > 0
        ? duration.inSeconds.toDouble()
        : 1.0;
    final sliderValue = (_dragValue ?? position.inSeconds.clamp(0, maxSeconds))
        .toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            trackHeight: 4,
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
          ),
          child: Slider(
            min: 0.0,
            value: sliderValue.clamp(0.0, maxSeconds),
            max: maxSeconds,
            onChanged: (value) => setState(() => _dragValue = value),
            onChangeEnd: (value) {
              ref
                  .read(playerProvider.notifier)
                  .seek(Duration(seconds: value.toInt()));
              setState(() => _dragValue = null);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(
                  _dragValue != null
                      ? Duration(seconds: _dragValue!.toInt())
                      : position,
                ),
                style: const TextStyle(color: Colors.white60),
              ),
              Text(
                _formatDuration(duration),
                style: const TextStyle(color: Colors.white60),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    final twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds'
        .replaceFirst('00:', '');
  }
}
