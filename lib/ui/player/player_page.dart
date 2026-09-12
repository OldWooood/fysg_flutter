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
import '../../utils/constants.dart';
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
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    final lyrics = ref.watch(_lyricsCacheProvider(song?.lyrics));
    // 息屏跟随播放状态：之前进页面 enable、出页面 disable，
    // 后台仍在播也会被关掉。现只在播放时保持常亮。
    ref.listen(playerProvider.select((s) => s.isPlaying), (_, isPlaying) {
      if (isPlaying) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    });

    if (song == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      // 主题感知背景：之前写死黑底，深色/浅色主题全失效
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: Icon(
            Icons.keyboard_arrow_down,
            color: Theme.of(context).colorScheme.onSurface,
            size: 30,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
      ),
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        // 下拉关闭：阈值 600 过大且与歌词滚动打架，降到 300；
        // 歌词页激活时不拦截，交由列表滚动接管
        onVerticalDragEnd: (details) {
          if (_lyricsTabActive) return;
          final velocity = details.primaryVelocity ?? 0;
          if (velocity > 300 && Navigator.of(context).canPop()) {
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
                        // 大封面限 500px：之前全分辨率双解码（显示+取色）
                        memCacheWidth: 500,
                        memCacheHeight: 500,
                      ),
                    ),
                  ),
                  SizedBox(height: middleSpacing),
                  Text(
                    song.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize:
                          titleFontSize *
                          MediaQuery.textScalerOf(
                            context,
                          ).scale(1.0).clamp(0.8, 1.4),
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    song.artist ?? AppLocalizations.of(context).unknownArtist,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
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
  // 有界 LRU：之前是无界静态 Map，切歌越多内存越大
  static final _paletteCache = <String, Color>{};
  static final _paletteOrder = <String>[];
  static const _fallbackColor = Color(0xFF20242E);
  Color _dominantColor = _fallbackColor;
  int _extractToken = 0;

  static void _putPalette(String url, Color color) {
    _paletteCache.remove(url);
    _paletteOrder.remove(url);
    _paletteCache[url] = color;
    _paletteOrder.add(url);
    while (_paletteOrder.length > AppConstants.paletteCacheMaxEntries) {
      final evicted = _paletteOrder.removeAt(0);
      _paletteCache.remove(evicted);
    }
  }

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
    final token = ++_extractToken;
    final url = widget.coverUrl;
    if (url == null || url.isEmpty) {
      if (mounted) setState(() => _dominantColor = _fallbackColor);
      return;
    }
    final cached = _paletteCache[url];
    if (cached != null) {
      if (mounted) setState(() => _dominantColor = cached);
      return;
    }
    try {
      // 用小缩略图取色 + 切歌后延迟到空闲帧，避免封面切换瞬间卡 1~3 帧；
      // token 防止快速切歌时旧任务覆盖新封面颜色。
      await Future.delayed(const Duration(milliseconds: 300));
      if (token != _extractToken || !mounted) return;
      final palette = await PaletteGenerator.fromImageProvider(
        ResizeImage(
          CachedNetworkImageProvider(
            url,
            headers: ImageCacheService.headers,
            cacheManager: ImageCacheService.cacheManager,
          ),
          width: 100,
        ),
        maximumColorCount: 8,
      );
      if (token != _extractToken || !mounted) return;
      final color =
          palette.vibrantColor?.color ??
          palette.mutedColor?.color ??
          palette.dominantColor?.color;
      if (color != null) {
        _putPalette(url, color);
        setState(() => _dominantColor = color);
      }
    } catch (_) {
      // 取色失败保持默认背景
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 深浅各一套：浅色用取色+白，深色用取色+黑，避免播放页永远纯黑
    final baseColor = isDark ? Colors.black : Colors.white;
    final topColor = Color.lerp(_dominantColor, baseColor, 0.35)!;
    final bottomColor = isDark ? Colors.black : colorScheme.surface;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topColor, bottomColor],
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

class _LyricsViewState extends ConsumerState<_LyricsView>
    with WidgetsBindingObserver {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  bool _userScrolling = false;
  Timer? _scrollTimer;
  int _lastScrolledIndex = -1;
  bool _scrollScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 退后台时停止“用户手滑后恢复自动滚动”的 Timer，避免后台空转
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _scrollTimer?.cancel();
      _scrollTimer = null;
    }
  }

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
    WidgetsBinding.instance.removeObserver(this);
    _scrollTimer?.cancel();
    _scrollTimer = null;
    super.dispose();
  }

  void _markUserScrolling() {
    _userScrolling = true;
    _scrollTimer?.cancel();
  }

  void _scheduleResumeAutoScroll() {
    _scrollTimer?.cancel();
    _scrollTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _userScrolling = false;
    });
  }

  /// build() 内只做调度，真正的 scrollTo 放到 post-frame，
  /// 避免每 position tick 在 build 期间直接滚动（违反 build 纯函数 + 高频滚动）。
  void _scheduleScrollToCurrentLine(int index) {
    if (_userScrolling ||
        index < 0 ||
        index == _lastScrolledIndex ||
        _scrollScheduled) {
      return;
    }
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || _userScrolling) return;
      _scrollToCurrentLine(index);
    });
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
    // 秒级订阅：之前 watch Duration 全精度，100ms 重建整个歌词列表
    final positionSeconds = ref.watch(
      playerProvider.select((s) => s.position.inSeconds),
    );
    final position = Duration(seconds: positionSeconds);
    // 跟随系统字体缩放：之前固定 24/18，大字体用户看不清
    final textScaler = MediaQuery.textScalerOf(
      context,
    ).scale(1.0).clamp(0.8, 1.6);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final onSurfaceDim = onSurface.withValues(alpha: 0.6);

    if (widget.lyrics.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).noLyrics,
          style: TextStyle(color: onSurface),
        ),
      );
    }

    final currentIndex = findCurrentLyricIndex(widget.lyrics, position);
    if (currentIndex != -1 && widget.active) {
      _scheduleScrollToCurrentLine(currentIndex);
    }

    return Listener(
      // 滑动手势（drag/pan）同样视为用户接管，而不只是 tap
      onPointerDown: (_) => _markUserScrolling(),
      onPointerUp: (_) => _scheduleResumeAutoScroll(),
      onPointerCancel: (_) => _scheduleResumeAutoScroll(),
      child: GestureDetector(
        onTapDown: (_) => _markUserScrolling(),
        onTapUp: (_) => _scheduleResumeAutoScroll(),
        onVerticalDragStart: (_) => _markUserScrolling(),
        onVerticalDragEnd: (_) => _scheduleResumeAutoScroll(),
        onHorizontalDragStart: (_) => _markUserScrolling(),
        onHorizontalDragEnd: (_) => _scheduleResumeAutoScroll(),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            // 用户主动滚动时暂停自动跟随；滚动结束 2s 后恢复
            if (notification is ScrollStartNotification &&
                notification.dragDetails != null) {
              _markUserScrolling();
            } else if (notification is ScrollEndNotification) {
              _scheduleResumeAutoScroll();
            }
            return false;
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
              child: Semantics(
                selected: isCurrent,
                child: Text(
                  widget.lyrics[index].text,
                  style: TextStyle(
                    color: isCurrent ? onSurface : onSurfaceDim,
                    fontSize: (isCurrent ? 24 : 18) * textScaler,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        },
          ),
        ),
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final onSurfaceDim = onSurface.withValues(alpha: 0.6);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // TabBar moved here
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: TabBar(
            controller: tabController,
            indicatorColor: onSurface,
            labelColor: onSurface,
            unselectedLabelColor: onSurfaceDim,
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Semantics(
          button: true,
          label: MaterialLocalizations.of(context).previousPageTooltip,
          child: IconButton(
            tooltip: MaterialLocalizations.of(context).previousPageTooltip,
            icon: Icon(Icons.skip_previous, color: onSurface, size: 40),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => ref.read(playerProvider.notifier).previous(),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onSurface,
          ),
          child: Semantics(
            button: true,
            label: isPlaying
                ? AppLocalizations.of(context).pause
                : AppLocalizations.of(context).play,
            child: IconButton(
              tooltip: isPlaying
                  ? AppLocalizations.of(context).pause
                  : AppLocalizations.of(context).play,
              icon: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: Theme.of(context).colorScheme.surface,
                size: 40,
              ),
              constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
              onPressed: () =>
                  ref.read(playerProvider.notifier).togglePlayPause(),
            ),
          ),
        ),
        Semantics(
          button: true,
          label: MaterialLocalizations.of(context).nextPageTooltip,
          child: IconButton(
            tooltip: MaterialLocalizations.of(context).nextPageTooltip,
            icon: Icon(Icons.skip_next, color: onSurface, size: 40),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => ref.read(playerProvider.notifier).next(),
          ),
        ),
      ],
    );
  }

  Future<void> _downloadCurrent(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(playerProvider.notifier);
    // 先快检已下载，避免弹进度框
    final quick = await notifier.downloadCurrentSong();
    if (quick == null || !context.mounted) return;
    final l10n = AppLocalizations.of(context);
    if (quick == DownloadResult.alreadyDownloaded) {
      ToastUtils.showToast(context, l10n.alreadyDownloaded);
      return;
    }
    if (quick == DownloadResult.failed) {
      ToastUtils.showError(context, l10n.downloadFailed);
      return;
    }
    // 已以后台启动（quick == started），再用进度框做二次确认展示：
    // 为避免重复下载，这里仅提示；真正的进度展示走 Mine/通知。
    // 若需要精确进度，可在 downloadCurrentSong(onProgress:) 基础上接 LinearProgressIndicator。
    ToastUtils.showToast(context, l10n.downloadStarted);
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

  static const _speedOptions = [0.75, 1.0, 1.25, 1.5, 2.0];

  Future<void> _pickSpeed(
    BuildContext context,
    WidgetRef ref,
    double current,
  ) async {
    // 之前循环 1->1.25->1.5->0.75，第三次突然变慢；改弹窗单选
    final picked = await showDialog<double>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(AppLocalizations.of(context).speed),
        children: _speedOptions
            .map(
              (s) => ListTile(
                title: Text('${_formatSpeed(s)}x'),
                trailing: s == current
                    ? Icon(
                        Icons.check,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.of(context).pop(s),
              ),
            )
            .toList(),
      ),
    );
    if (picked != null) {
      ref.read(playerProvider.notifier).setSpeed(picked);
    }
  }

  Future<void> _pickSleepTimer(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final current = ref.read(sleepTimerProvider);
    Duration? picked;
    var chose = false;
    await showDialog<void>(
      context: context,
      builder: (context) {
        Widget item(Duration? value, String label) {
          final selected = value == current;
          return ListTile(
            title: Text(label),
            trailing: selected
                ? Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
            onTap: () {
              picked = value;
              chose = true;
              Navigator.of(context).pop();
            },
          );
        }

        return SimpleDialog(
          title: Text(l10n.sleepTimer),
          children: [
            item(null, l10n.sleepOff),
            item(const Duration(minutes: 15), '15 min'),
            item(const Duration(minutes: 30), '30 min'),
            item(const Duration(minutes: 60), '60 min'),
          ],
        );
      },
    );
    if (!context.mounted || !chose) return;
    {
      ref.read(playerProvider.notifier).setSleepTimer(picked);
      if (picked != null && context.mounted) {
        ToastUtils.showToast(context, l10n.sleepTimer);
      }
    }
  }

  Widget _buildOptionButtons(
    BuildContext context,
    WidgetRef ref,
    Song? song,
    PlaybackMode mode,
    double speed,
  ) {
    final l10n = AppLocalizations.of(context);
    final sleepTimer = ref.watch(sleepTimerProvider);
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
            onPressed: () => _pickSpeed(context, ref, speed),
          ),
          _buildOptionButton(
            context,
            icon: sleepTimer != null
                ? Icons.bedtime
                : Icons.bedtime_outlined,
            label: sleepTimer != null
                ? '${sleepTimer.inMinutes}min'
                : l10n.sleepTimer,
            onPressed: () => _pickSleepTimer(context, ref),
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final onSurfaceDim = onSurface.withValues(alpha: 0.7);
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
                Icon(icon, color: onSurface, size: 26),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: onSurfaceDim, fontSize: 11),
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
    // 秒级订阅：之前同时 watch position+duration，just_audio ~100ms 推一次导致
    // 全量 rebuild；取秒后降为 1次/s，拖动期间用 _dragValue 本地值不被打断。
    final durationSeconds = ref.watch(
      playerProvider.select((s) => s.duration.inSeconds),
    );
    final positionSeconds = ref.watch(
      playerProvider.select((s) => s.position.inSeconds),
    );
    final duration = Duration(seconds: durationSeconds);
    final position = Duration(seconds: positionSeconds);

    final maxSeconds = duration.inSeconds > 0
        ? duration.inSeconds.toDouble()
        : 1.0;
    final sliderValue = (_dragValue ?? position.inSeconds.clamp(0, maxSeconds))
        .toDouble();
    final hasDuration = duration.inSeconds > 0;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final onSurfaceDim = onSurface.withValues(alpha: 0.6);

    return Semantics(
      slider: true,
      value: '${_formatDuration(position)}/${_formatDuration(duration)}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              // 增大触摸目标：之前 thumb 6/track 4 难拖
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              trackHeight: 4,
              activeTrackColor: onSurface,
              inactiveTrackColor: onSurface.withValues(alpha: 0.24),
              thumbColor: onSurface,
            ),
            child: Slider(
              min: 0.0,
              value: sliderValue.clamp(0.0, maxSeconds),
              max: maxSeconds,
              // 无时长时禁用，避免 thumb 卡 0 无反馈
              onChanged: hasDuration
                  ? (value) => setState(() => _dragValue = value)
                  : null,
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
                  style: TextStyle(color: onSurfaceDim),
                ),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(color: onSurfaceDim),
                ),
              ],
            ),
          ),
        ],
      ),
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
