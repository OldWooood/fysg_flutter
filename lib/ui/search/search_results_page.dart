import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api/fysg_service.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../common/mini_player.dart';
import '../../l10n/app_localizations.dart';
import '../../api/image_cache_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SearchResultsPage extends ConsumerStatefulWidget {
  final String query;
  const SearchResultsPage({Key? key, required this.query}) : super(key: key);

  @override
  ConsumerState<SearchResultsPage> createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends ConsumerState<SearchResultsPage> {
  final ScrollController _scrollController = ScrollController();
  List<Song> _results = [];
  int _currentPage = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _performInitialSearch();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore) {
        _loadMore();
      }
    }
  }

  Future<void> _performInitialSearch() async {
    setState(() => _isLoading = true);
    try {
      final results = await ref.read(fysgServiceProvider).searchSongs(widget.query, page: 0);
      if (mounted) {
        setState(() {
          _results = results;
          _hasMore = results.length >= 20;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _isLoadingMore = true);
    final nextPage = _currentPage + 1;
    try {
      final songs = await ref.read(fysgServiceProvider).searchSongs(widget.query, page: nextPage);
      if (mounted) {
        setState(() {
          _results.addAll(songs);
          _currentPage = nextPage;
          _hasMore = songs.length >= 20;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
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
      appBar: AppBar(
        title: Text('${AppLocalizations.of(context).searchAction}: ${widget.query}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? Center(child: Text(AppLocalizations.of(context).noResults))
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _results.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _results.length) {
                            return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator()));
                          }
                          final song = _results[index];
                          return ListTile(
                            leading: song.cover != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: CachedNetworkImage(
                                      imageUrl: song.cover!,
                                      httpHeaders: ImageCacheService.headers,
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                    ))
                                : const Icon(Icons.music_note, size: 40),
                            title: Text(
                              song.name, 
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)
                            ),
                            subtitle: Text(
                              song.artist ?? 'Unknown',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                            ),
                            onTap: () {
                              ref.read(playerProvider.notifier).logQueue(_results, index);
                            },
                          );
                        },
                      ),
          ),
          const MiniPlayer(),
        ],
      ),
    );
  }
}
