import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../api/fysg_service.dart';
import '../../api/recently_played_service.dart';
import '../../api/image_cache_service.dart';
import '../../models/song.dart';
import '../search/search_page.dart';
import '../common/mini_player.dart';
import '../recent/recently_played_page.dart';
import '../../providers/player_provider.dart';
import '../../l10n/app_localizations.dart';

final recentlyPlayedProvider = FutureProvider<List<Song>>((ref) async {
  return ref.read(recentlyPlayedServiceProvider).getRecentSongs();
});

class HomePage extends ConsumerStatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final ScrollController _scrollController = ScrollController();
  List<Song> _recommendedSongs = [];
  int _currentPage = 0;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _fetchInitialData() async {
      final songs = await ref.read(fysgServiceProvider).getRecommendedSongs(page: 0);
      if (mounted) {
          setState(() {
              _recommendedSongs = songs;
              _currentPage = 0;
              _hasMore = songs.length >= 20;
          });
      }
  }

  void _onScroll() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
          if (!_isLoadingMore && _hasMore) {
              _loadMore();
          }
      }
  }

  Future<void> _loadMore() async {
      setState(() {
          _isLoadingMore = true;
      });
      
      final nextPage = _currentPage + 1;
      final songs = await ref.read(fysgServiceProvider).getRecommendedSongs(page: nextPage);
      
      if (mounted) {
          setState(() {
              _recommendedSongs.addAll(songs);
              _currentPage = nextPage;
              _isLoadingMore = false;
              _hasMore = songs.length >= 20;
          });
      }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recentAsync = ref.watch(recentlyPlayedProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Text(AppLocalizations.of(context).appTitle, style: Theme.of(context).textTheme.displayMedium),
                ],
              ),
            ),
            
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [

                   // Recently Played Section
                   SliverToBoxAdapter(
                     child: recentAsync.when(
                       data: (songs) {
                           if (songs.isEmpty) return const SizedBox.shrink();
                           return Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                   Padding(
                                     padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
                                     child: Row(
                                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                       children: [
                                          Text(AppLocalizations.of(context).recentlyPlayed, style: Theme.of(context).textTheme.headlineSmall),
                                          TextButton(
                                              onPressed: () {
                                                  Navigator.push(context, MaterialPageRoute(builder: (_) => const RecentlyPlayedPage()));
                                              },
                                              child: Text(AppLocalizations.of(context).seeAll),
                                          )
                                       ],
                                     ),
                                   ),
                                   SizedBox(
                                       height: 160,
                                       child: ListView.builder(
                                           scrollDirection: Axis.horizontal,
                                           padding: const EdgeInsets.symmetric(horizontal: 20),
                                           itemCount: songs.length,
                                           itemBuilder: (context, index) {
                                               final song = songs[index];
                                               return GestureDetector(
                                                   onTap: () => ref.read(playerProvider.notifier).logQueue(songs, index),
                                                   child: Container(
                                                       width: 120,
                                                       margin: const EdgeInsets.only(right: 15),
                                                       child: Column(
                                                           crossAxisAlignment: CrossAxisAlignment.start,
                                                           children: [
                                                               AspectRatio(
                                                                   aspectRatio: 1,
                                                                   child: ClipRRect(
                                                                       borderRadius: BorderRadius.circular(8),
                                                                       child: song.cover != null 
                                                                        ? CachedNetworkImage(
                                                                            imageUrl: song.cover!,
                                                                            httpHeaders: ImageCacheService.headers,
                                                                            fit: BoxFit.cover,
                                                                         )
                                                                        : Container(color: Colors.grey),
                                                                   ),
                                                               ),
                                                                const SizedBox(height: 5),
                                                                Text(
                                                                  song.name, 
                                                                  maxLines: 2, 
                                                                  overflow: TextOverflow.ellipsis, 
                                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                                ),
                                                            ],
                                                       ),
                                                   ),
                                               );
                                           },
                                       ),
                                   ),
                               ],
                           );
                       },
                       loading: () => const SizedBox.shrink(),
                       error: (e, s) => const SizedBox.shrink(),
                     ),
                   ),

                   SliverToBoxAdapter(
                      child: Padding(
                       padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
                       child: Text(AppLocalizations.of(context).recommended, style: Theme.of(context).textTheme.headlineSmall),
                     ),
                   ),

                   // Recommended List
                   SliverList(
                     delegate: SliverChildBuilderDelegate(
                       (context, index) {
                           if (index == _recommendedSongs.length) {
                               return _isLoadingMore 
                                   ? const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                                   : const SizedBox(height: 100);
                           }
                           final song = _recommendedSongs[index];
                           return ListTile(
                               contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                               leading: song.cover != null 
                                   ? ClipRRect(
                                       borderRadius: BorderRadius.circular(4),
                                       child: CachedNetworkImage(
                                            imageUrl: song.cover!,
                                            httpHeaders: ImageCacheService.headers,
                                            width: 50,
                                            height: 50,
                                            fit: BoxFit.cover,
                                        )
                                   )
                                   : Container(color: Colors.grey, width: 50),
                               title: Text(
                                   song.name, 
                                   maxLines: 2,
                                   overflow: TextOverflow.ellipsis,
                                   style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)
                               ),
                               subtitle: Text(
                                   song.artist ?? "", 
                                   maxLines: 2,
                                   overflow: TextOverflow.ellipsis,
                                   style: const TextStyle(fontSize: 14)
                               ),
                               onTap: () {
                                   ref.invalidate(recentlyPlayedProvider);
                                   ref.read(playerProvider.notifier).logQueue(_recommendedSongs, index);
                               },
                           );
                       },
                       childCount: _recommendedSongs.length + 1,
                     ),
                   ),
                ],
              ),
            ),
             const MiniPlayer(),
          ],
        ),
       ),
    );
  }
}
