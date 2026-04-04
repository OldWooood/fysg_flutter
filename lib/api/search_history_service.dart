import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/shared_preferences_provider.dart';
import '../utils/constants.dart';

final searchHistoryServiceProvider = Provider((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SearchHistoryService(prefs);
});

final searchHistoryProvider = FutureProvider<List<String>>((ref) async {
  return ref.watch(searchHistoryServiceProvider).getHistory();
});

class SearchHistoryService {
  static const int _maxItems = 20;
  final SharedPreferences _prefs;

  SearchHistoryService(this._prefs);

  Future<void> addQuery(String query) async {
    if (query.trim().isEmpty) return;
    List<String> history =
        _prefs.getStringList(AppConstants.spSearchHistory) ?? [];

    // Remove if existing
    history.removeWhere(
      (item) => item.toLowerCase() == query.trim().toLowerCase(),
    );

    // Add to top
    history.insert(0, query.trim());

    // Limit
    if (history.length > _maxItems) {
      history = history.sublist(0, _maxItems);
    }

    await _prefs.setStringList(AppConstants.spSearchHistory, history);
  }

  Future<List<String>> getHistory() async {
    return _prefs.getStringList(AppConstants.spSearchHistory) ?? [];
  }

  Future<void> clearHistory() async {
    await _prefs.remove(AppConstants.spSearchHistory);
  }
}
