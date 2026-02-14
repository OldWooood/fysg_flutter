import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../api/fysg_service.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../common/mini_player.dart';
import '../../l10n/app_localizations.dart';
import '../../api/image_cache_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../api/search_history_service.dart';

class SearchResultsPage extends ConsumerStatefulWidget {
  final String query;
  const SearchResultsPage({Key? key, required this.query}) : super(key: key);

  @override
  ConsumerState<SearchResultsPage> createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends ConsumerState<SearchResultsPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoadingSuggestions = false;
  List<Song> _results = [];
  int _currentPage = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  late String _currentQuery;

  @override
  void initState() {
    super.initState();
    _currentQuery = widget.query;
    _searchController.text = _currentQuery;
    _searchController.addListener(_onSearchChanged);
    _performInitialSearch();
    _scrollController.addListener(_onScroll);
  }

  void _onSearchChanged() {
    // We only show suggestions if the text is different from the current search results query
    final query = _searchController.text;
    if (query == _currentQuery) {
      if (mounted) {
        setState(() {
          _suggestions = [];
          _isLoadingSuggestions = false;
        });
      }
      return;
    }

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final q = _searchController.text;
      if (q.isEmpty || q == _currentQuery) {
        if (mounted) {
          setState(() {
            _suggestions = [];
            _isLoadingSuggestions = false;
          });
        }
        return;
      }

      if (mounted) setState(() => _isLoadingSuggestions = true);
      try {
        final suggestions = await ref.read(fysgServiceProvider).getSearchSuggestions(q);
        if (mounted) {
          setState(() {
            _suggestions = suggestions;
            _isLoadingSuggestions = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isLoadingSuggestions = false);
      }
    });
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
      final results = await ref.read(fysgServiceProvider).searchSongs(_currentQuery, page: 0);
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
      final songs = await ref.read(fysgServiceProvider).searchSongs(_currentQuery, page: nextPage);
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

  void _newSearch(String query) async {
    if (query.isEmpty || query == _currentQuery) return;
    
    await ref.read(searchHistoryServiceProvider).addQuery(query);
    ref.invalidate(searchHistoryProvider);

    setState(() {
      _currentQuery = query;
      _currentPage = 0;
      _results = [];
      _isLoading = true;
      _suggestions = [];
    });
    _performInitialSearch();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(25),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: Colors.grey, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(fontSize: 16),
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context).searchHint,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    suffixIcon: _searchController.text.isNotEmpty 
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  ),
                  onChanged: (v) {
                    setState(() {}); // Trigger rebuild to show suggestions if query changed
                  },
                  onSubmitted: _newSearch,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _newSearch(_searchController.text),
            child: Text(
              AppLocalizations.of(context).searchAction,
              style: TextStyle(
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: (_searchController.text.isNotEmpty && _searchController.text != _currentQuery)
                ? _buildSuggestions()
                : _isLoading
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

  Widget _buildSuggestions() {
    if (_isLoadingSuggestions || (_suggestions.isEmpty && _searchController.text.isNotEmpty && _debounce?.isActive == true)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_suggestions.isEmpty && _searchController.text.isNotEmpty) {
      return Center(child: Text(AppLocalizations.of(context).noResults));
    }
    return ListView.builder(
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = _suggestions[index];
        return ListTile(
          leading: const Icon(Icons.search, color: Colors.grey),
          title: Text(suggestion['name'] ?? ''),
          onTap: () => _newSearch(suggestion['name'] ?? ''),
        );
      },
    );
  }
}
