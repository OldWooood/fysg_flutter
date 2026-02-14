import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/playlist.dart';
import '../../providers/player_provider.dart';
import '../../api/image_cache_service.dart';
import '../common/mini_player.dart';
import 'playlist_detail_page.dart';
import '../../l10n/app_localizations.dart';

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).browse, style: const TextStyle(fontFamily: 'Playfair Display', fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Theme.of(context).primaryColor,
          tabs: [
            Tab(text: AppLocalizations.of(context).albums),
            Tab(text: AppLocalizations.of(context).playlists),
            Tab(text: AppLocalizations.of(context).authors),
            Tab(text: AppLocalizations.of(context).books),
          ],
        ),
      ),
      body: Column(
        children: [
            Expanded(
                child: TabBarView(
                    controller: _tabController,
                    children: [
                        _CategoryGrid(type: 'album'),
                        _CategoryGrid(type: 'playlist'),
                        _CategoryGrid(type: 'author'),
                        _CategoryGrid(type: 'book'),
                    ],
                ),
            ),
            const MiniPlayer(),
        ],
      ),
    );
  }
}

class _CategoryGrid extends ConsumerStatefulWidget {
  final String type;
  const _CategoryGrid({required this.type});

  @override
  ConsumerState<_CategoryGrid> createState() => _CategoryGridState();
}

class _CategoryGridState extends ConsumerState<_CategoryGrid> {
  final ScrollController _scrollController = ScrollController();
  List<Playlist> _items = [];
  int _currentPage = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _fetchInitialData() async {
    final service = ref.read(fysgServiceProvider);
    List<Playlist> items = [];
    
    try {
        if (widget.type == 'album') items = await service.getAlbums(page: 0);
        else if (widget.type == 'playlist') items = await service.getPlaylists(page: 0);
        else if (widget.type == 'author') items = await service.getAuthors(page: 0);
        else if (widget.type == 'book') items = await service.getBooks(page: 0);
    } catch (e) {
        print('Error fetching ${widget.type}: $e');
    }

    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
        _hasMore = items.length >= 20;
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
      
      final service = ref.read(fysgServiceProvider);
      final nextPage = _currentPage + 1;
      List<Playlist> items = [];

      try {
          if (widget.type == 'album') items = await service.getAlbums(page: nextPage);
          else if (widget.type == 'playlist') items = await service.getPlaylists(page: nextPage);
          else if (widget.type == 'author') items = await service.getAuthors(page: nextPage);
          else if (widget.type == 'book') items = await service.getBooks(page: nextPage);
      } catch (e) {
          print('Error loading more ${widget.type}: $e');
      }

      if (mounted) {
          setState(() {
              _items.addAll(items);
              _currentPage = nextPage;
              _isLoadingMore = false;
              _hasMore = items.length >= 20;
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
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _items.length + (_isLoadingMore ? 2 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
            return const Center(child: CircularProgressIndicator());
        }
        final item = _items[index];
        return GestureDetector(
          onTap: () {
             Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistDetailPage(playlist: item)));
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey[200],
                    image: item.cover != null ? DecorationImage(
                        image: CachedNetworkImageProvider(
                            item.cover!, 
                            headers: ImageCacheService.headers
                        ),
                        fit: BoxFit.cover,
                    ) : null,
                  ),
                  child: item.cover == null ? const Center(child: Icon(Icons.music_note, size: 40, color: Colors.grey)) : null,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
      },
    );
  }
}
