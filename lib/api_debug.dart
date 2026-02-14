import 'api/fysg_service.dart';

void main() async {
  final service = FysgService();
  print('Testing Search...');
  try {
    final results = await service.searchSongs('hymn');
    print('Search Results: ${results.length}');
    if (results.isNotEmpty) {
      print('First result: ${results[0].name} - URL: ${results[0].url}');
    } else {
        print('Search returned empty list.');
    }
  } catch (e) {
    print('Search Error: $e');
  }

  print('\nTesting Recommendations...');
  try {
      final results = await service.getRecommendedSongs();
      print('Recommendation Results: ${results.length}');
      if (results.isNotEmpty) {
          print('First Rec: ${results[0].name} - URL: ${results[0].url}');
      }
  } catch (e) {
      print('Rec Error: $e');
  }
}
