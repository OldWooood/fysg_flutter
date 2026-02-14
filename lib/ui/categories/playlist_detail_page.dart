import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/playlist.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../api/image_cache_service.dart';
import '../common/mini_player.dart';
import '../../l10n/app_localizations.dart';

class PlaylistDetailPage extends ConsumerStatefulWidget {
  final Playlist playlist;

  const PlaylistDetailPage({super.key, required this.playlist});

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  final ScrollController _scrollController = ScrollController();
  List<Song> _songs = [];
  int _currentPage = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _fetchInitialSongs();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
          if (!_isLoadingMore && _hasMore) {
              _loadMore();
          }
      }
  }

  Future<void> _fetchInitialSongs() async {
    final service = ref.read(fysgServiceProvider);
    try {
        final songs = await service.getCollectionSongs(widget.playlist.type, widget.playlist.id, page: 0);
        if (mounted) {
            setState(() {
                _songs = songs;
                _isLoading = false;
                _hasMore = songs.length >= 20;
            });
        }
    } catch (e) {
        if (mounted) {
            setState(() {
                _isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading songs: $e')));
        }
    }
  }

  Future<void> _loadMore() async {
      setState(() {
          _isLoadingMore = true;
      });
      
      final service = ref.read(fysgServiceProvider);
      final nextPage = _currentPage + 1;
      try {
          final songs = await service.getCollectionSongs(widget.playlist.type, widget.playlist.id, page: nextPage);
          if (mounted) {
              setState(() {
                  _songs.addAll(songs);
                  _currentPage = nextPage;
                  _isLoadingMore = false;
                  _hasMore = songs.length >= 20;
              });
          }
      } catch (e) {
          if (mounted) {
              setState(() {
                  _isLoadingMore = false;
              });
          }
      }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
     return Scaffold(
         body: Column(
             children: [
                 Expanded(
                     child: CustomScrollView(
                         controller: _scrollController,
                         slivers: [
                             SliverAppBar(
                                 expandedHeight: 250,
                                 pinned: true,
                                 flexibleSpace: FlexibleSpaceBar(
                                     title: Text(
                                         widget.playlist.name, 
                                         maxLines: 2,
                                         overflow: TextOverflow.ellipsis,
                                         style: const TextStyle(
                                             color: Colors.white, 
                                             shadows: [Shadow(color: Colors.black, blurRadius: 10)]
                                         )
                                     ),
                                     background: widget.playlist.cover != null ? 
                                        CachedNetworkImage(
                                            imageUrl: widget.playlist.cover!,
                                            httpHeaders: ImageCacheService.headers,
                                            fit: BoxFit.cover,
                                        ) : Container(color: Theme.of(context).primaryColor),
                                 ),
                             ),
                             if (!_isLoading && _songs.isNotEmpty)
                                 SliverToBoxAdapter(
                                     child: Padding(
                                         padding: const EdgeInsets.all(16.0),
                                         child: ElevatedButton.icon(
                                             onPressed: () {
                                                 ref.read(playerProvider.notifier).logQueue(_songs, 0);
                                             },
                                             icon: const Icon(Icons.play_arrow),
                                             label: Text(AppLocalizations.of(context).playAll, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                             style: ElevatedButton.styleFrom(
                                                 backgroundColor: Theme.of(context).primaryColor,
                                                 foregroundColor: Colors.white,
                                                 padding: const EdgeInsets.symmetric(vertical: 12),
                                                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                             ),
                                         ),
                                     ),
                                 ),
                             if (_isLoading)
                                 const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
                             else ...[
                                SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                        (context, index) {
                                            final song = _songs[index];
                                            final isPlaying = ref.watch(playerProvider.select((s) => s.currentSong?.id == song.id));
                                            
                                            return ListTile(
                                                leading: Text('${index + 1}', style: const TextStyle(color: Colors.grey, fontSize: 16)),
                                                title: Text(
                                                    song.name, 
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        color: isPlaying ? Theme.of(context).primaryColor : null
                                                    )
                                                ),
                                                subtitle: Text(
                                                    song.artist ?? '', 
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(fontSize: 12)
                                                ),
                                                trailing: const Icon(Icons.play_circle_outline),
                                                onTap: () {
                                                    ref.read(playerProvider.notifier).logQueue(_songs, index);
                                                },
                                            );
                                        },
                                        childCount: _songs.length,
                                    ),
                                ),
                                if (_isLoadingMore)
                                    const SliverToBoxAdapter(
                                        child: Padding(
                                            padding: EdgeInsets.all(16),
                                            child: Center(child: CircularProgressIndicator()),
                                        ),
                                    ),
                                const SliverToBoxAdapter(child: SizedBox(height: 100)),
                             ],
                         ],
                     ),
                 ),
                 const MiniPlayer(),
             ],
         ),
     );
  }
}
