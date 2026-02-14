import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SearchHistoryService {
  static const String _key = 'search_history';
  static const int _maxItems = 20;

  Future<void> addQuery(String query) async {
    if (query.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList(_key) ?? [];
    
    // Remove if existing
    history.removeWhere((item) => item.toLowerCase() == query.trim().toLowerCase());
    
    // Add to top
    history.insert(0, query.trim());
    
    // Limit
    if (history.length > _maxItems) {
      history = history.sublist(0, _maxItems);
    }
    
    await prefs.setStringList(_key, history);
  }

  Future<List<String>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

final searchHistoryServiceProvider = Provider((ref) => SearchHistoryService());

final searchHistoryProvider = FutureProvider<List<String>>((ref) async {
  return ref.watch(searchHistoryServiceProvider).getHistory();
});
