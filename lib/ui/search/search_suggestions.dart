import 'package:flutter/material.dart';

/// 搜索建议共用列表（之前 search_page / search_results_page 各写一套）。
class SearchSuggestionsList extends StatelessWidget {
  final List<Map<String, dynamic>> suggestions;
  final ValueChanged<String> onSelect;
  final bool highlight;
  final String query;

  const SearchSuggestionsList({
    super.key,
    required this.suggestions,
    required this.onSelect,
    this.highlight = false,
    this.query = '',
  });

  static String artistOf(Map<String, dynamic> suggestion) {
    final artist = suggestion['artist'];
    if (artist is Map) return '${(artist)['name'] ?? ''}';
    return '${suggestion['artist'] ?? suggestion['author'] ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = suggestions[index];
        final name = '${suggestion['name'] ?? ''}';
        final artist = artistOf(suggestion);
        return ListTile(
          leading: Icon(Icons.search, color: Theme.of(context).hintColor),
          title: highlight
              ? highlightQuery(name, query, context)
              : Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          subtitle: artist.isEmpty
              ? null
              : Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          onTap: () => onSelect(name),
        );
      },
    );
  }
}

/// 搜索关键字高亮：之前只显示歌名无反馈
Widget highlightQuery(String text, String query, BuildContext context) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty || !text.toLowerCase().contains(q)) {
    return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
  }
  final lower = text.toLowerCase();
  final start = lower.indexOf(q);
  final end = start + q.length;
  final primary = Theme.of(context).colorScheme.primary;
  return RichText(
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    text: TextSpan(
      style: DefaultTextStyle.of(context).style,
      children: [
        TextSpan(text: text.substring(0, start)),
        TextSpan(
          text: text.substring(start, end),
          style: TextStyle(color: primary, fontWeight: FontWeight.bold),
        ),
        TextSpan(text: text.substring(end)),
      ],
    ),
  );
}
