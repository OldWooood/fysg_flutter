import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../common/mini_player.dart';
import '../common/song_list_tile.dart';
import '../../l10n/app_localizations.dart';
import '../../api/search_history_service.dart';

class SearchResultsPage extends ConsumerStatefulWidget {
  final String query;
  const SearchResultsPage({Key? key, required this.query}) : super(key: key);

  @override
  ConsumerState<SearchResultsPage> createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends ConsumerState<SearchResultsPage> {
  static const _pageSize = 20;
  static const _loadMoreTriggerExtent = 600.0;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  Timer? _scrollDebounce;
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
        final suggestions = await ref
            .read(fysgServiceProvider)
            .getSearchSuggestions(q);
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
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) return;
    if (_scrollController.position.extentAfter > _loadMoreTriggerExtent) return;
    if (_scrollDebounce?.isActive ?? false) return;
    _scrollDebounce = Timer(const Duration(milliseconds: 120), _loadMore);
  }

  Future<void> _performInitialSearch() async {
    setState(() => _isLoading = true);
    try {
      final results = await ref
          .read(fysgServiceProvider)
          .searchSongs(_currentQuery, page: 0);
      final filtered = _filterPlayable(results);
      if (mounted) {
        setState(() {
          _results = filtered;
          _hasMore = results.length >= _pageSize;
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
      final songs = await ref
          .read(fysgServiceProvider)
          .searchSongs(_currentQuery, page: nextPage);
      final filtered = _filterPlayable(songs);
      if (mounted) {
        setState(() {
          _results.addAll(filtered);
          _currentPage = nextPage;
          _hasMore = songs.length >= _pageSize;
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
    _scrollDebounce?.cancel();
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
                    setState(
                      () {},
                    ); // Trigger rebuild to show suggestions if query changed
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
            child:
                (_searchController.text.isNotEmpty &&
                    _searchController.text != _currentQuery)
                ? _buildSuggestions()
                : _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                ? Center(child: Text(AppLocalizations.of(context).noResults))
                : ListView.builder(
                    controller: _scrollController,
                    cacheExtent: 800,
                    addAutomaticKeepAlives: false,
                    itemCount: _results.length + (_isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _results.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final song = _results[index];
                      return SongListTile(
                        key: ValueKey(song.id),
                        song: song,
                        onTap: () {
                          final queue = _buildPlaybackQueue(_results, index);
                          if (queue.isEmpty) return;
                          ref.read(playerProvider.notifier).logQueue(queue, 0);
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
    if (_isLoadingSuggestions ||
        (_suggestions.isEmpty &&
            _searchController.text.isNotEmpty &&
            _debounce?.isActive == true)) {
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

  bool _isPotentiallyPlayable(Song song) {
    final hasUrl = song.url?.trim().isNotEmpty ?? false;
    final hasResolvableId = song.id > 0;
    return hasUrl || hasResolvableId;
  }

  List<Song> _filterPlayable(List<Song> songs) {
    return songs.where(_isPotentiallyPlayable).toList();
  }

  List<Song> _buildPlaybackQueue(List<Song> songs, int tappedIndex) {
    if (songs.isEmpty) return const [];
    final safeIndex = tappedIndex.clamp(0, songs.length - 1);
    return [...songs.sublist(safeIndex), ...songs.sublist(0, safeIndex)];
  }
}
