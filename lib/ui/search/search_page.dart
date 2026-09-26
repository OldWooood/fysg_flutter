import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/search_history_service.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/player_provider.dart';
import '../../utils/constants.dart';
import 'search_results_page.dart';
import 'search_suggestions.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  CancelToken? _suggestCancel;
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoadingSuggestions = false;
  // 搜索竞态 token：慢请求后到不覆盖快请求（另有 CancelToken 直接取消旧请求）
  int _suggestToken = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    if (query.isEmpty) {
      _debounce?.cancel();
      _suggestToken++;
      setState(() {
        _suggestions = [];
        _isLoadingSuggestions = false;
      });
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(AppConstants.searchDebounceMs, () async {
      final currentQuery = _searchController.text;
      if (currentQuery.isEmpty) return;
      final token = ++_suggestToken;
      // 取消上一发未完成的建议请求，省流量
      _suggestCancel?.cancel('new query');
      final cancelToken = CancelToken();
      _suggestCancel = cancelToken;

      if (mounted) setState(() => _isLoadingSuggestions = true);
      try {
        final result = await ref
            .read(fysgServiceProvider)
            .getSearchSuggestions(currentQuery, cancelToken: cancelToken);

        if (!mounted || token != _suggestToken) return;

        result.when(
          ok: (suggestions) {
            setState(() {
              _suggestions = suggestions;
              _isLoadingSuggestions = false;
            });
          },
          err: (error) {
            // 被新输入取消不算失败，保持旧建议
            if (error.code == 'cancelled') return;
            setState(() => _isLoadingSuggestions = false);
          },
        );
      } catch (e) {
        if (mounted && token == _suggestToken) {
          setState(() => _isLoadingSuggestions = false);
        }
      }
    });
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    FocusScope.of(context).unfocus();

    await ref.read(searchHistoryServiceProvider).addQuery(trimmed);
    ref.invalidate(searchHistoryProvider);
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SearchResultsPage(query: trimmed)),
    );
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    _suggestCancel?.cancel('dispose');
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
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: Theme.of(context).hintColor),
              const SizedBox(width: 8),
              Expanded(
                // 输入框局部重建：之前 onChanged 整页 setState，每敲一字全量 rebuild
                child: ListenableBuilder(
                  listenable: _searchController,
                  builder: (context, _) => TextField(
                    controller: _searchController,
                    // 常驻 Tab 切过来自动弹键盘遮挡历史，改为手动聚焦
                    autofocus: false,
                    style: const TextStyle(fontSize: 16),
                    textAlignVertical: TextAlignVertical.center,
                    textInputAction: TextInputAction.search,
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
                              onPressed: _searchController.clear,
                            )
                          : null,
                    ),
                    onSubmitted: _performSearch,
                  ),
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
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _searchController,
        builder: (context, _) {
          if (_searchController.text.isNotEmpty) return _buildSuggestions();
          return historyAsync.when(
              data: (history) {
                if (history.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search,
                          size: 80,
                          color: Theme.of(context).hintColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          AppLocalizations.of(context).searchEmptyHint,
                          style: TextStyle(color: Theme.of(context).hintColor),
                        ),
                      ],
                    ),
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
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).clearHistory,
                                  ),
                                  content: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).clearHistoryConfirm,
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(
                                        context,
                                      ).pop(false),
                                      child: Text(
                                        AppLocalizations.of(context).cancel,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: Text(
                                        AppLocalizations.of(context).confirm,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true) return;
                              await ref
                                  .read(searchHistoryServiceProvider)
                                  .clearHistory();
                              ref.invalidate(searchHistoryProvider);
                            },
                            child: Text(
                              AppLocalizations.of(context).clearHistory,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        children: history
                            .map(
                              (query) => ActionChip(
                                label: Text(query),
                                onPressed: () => _performSearch(query),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) =>
                  Center(child: Text(AppLocalizations.of(context).loadFailed)),
            );
        },
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
    // 共用建议列表（含高亮），不再各页手写 ListTile
    return SearchSuggestionsList(
      suggestions: _suggestions,
      highlight: true,
      query: _searchController.text,
      onSelect: _performSearch,
    );
  }
}
