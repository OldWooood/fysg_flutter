import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../common/mini_player.dart';
import '../../l10n/app_localizations.dart';
import 'search_results_page.dart';
import '../../api/search_history_service.dart';

// Simple provider for search state
final searchResultsProvider = StateProvider<List<Song>>((ref) => []);
final isSearchingProvider = StateProvider<bool>((ref) => false);

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({Key? key}) : super(key: key);

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoadingSuggestions = false;
  
  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    if (query.isEmpty) {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      setState(() {
        _suggestions = [];
        _isLoadingSuggestions = false;
      });
      return;
    }

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final currentQuery = _searchController.text;
      if (currentQuery.isEmpty) return;

      if (mounted) setState(() => _isLoadingSuggestions = true);
      try {
        final suggestions = await ref.read(fysgServiceProvider).getSearchSuggestions(currentQuery);
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

  void _performSearch(String query) async {
    if (query.isEmpty) return;

    await ref.read(searchHistoryServiceProvider).addQuery(query);
    ref.invalidate(searchHistoryProvider);
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SearchResultsPage(query: query),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(searchHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(25),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
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
                    setState(() {}); // Trigger rebuild to switch to suggestions view
                  },
                  onSubmitted: _performSearch,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _performSearch(_searchController.text),
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
            child: _searchController.text.isNotEmpty
                ? _buildSuggestions()
                : historyAsync.when(
                    data: (history) {
                if (history.isEmpty) {
                  return const Center(
                    child: Icon(Icons.search, size: 100, color: Colors.grey),
                  );
                }
                return ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            AppLocalizations.of(context).searchHistory,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              await ref.read(searchHistoryServiceProvider).clearHistory();
                              ref.invalidate(searchHistoryProvider);
                            },
                            child: Text(AppLocalizations.of(context).clearHistory),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        children: history.map((query) => ActionChip(
                          label: Text(query),
                          onPressed: () => _performSearch(query),
                        )).toList(),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text('Error: $e')),
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
          onTap: () => _performSearch(suggestion['name'] ?? ''),
        );
      },
    );
  }
}
