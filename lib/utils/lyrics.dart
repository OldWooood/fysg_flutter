import 'package:flutter/foundation.dart';

/// 歌词行数据
@immutable
class LyricLine {
  final Duration offset;
  final String text;

  const LyricLine({required this.offset, required this.text});
}

/// 解析 LRC 格式歌词
List<LyricLine> parseLyrics(String? lrc) {
  if (lrc == null || lrc.isEmpty) return const [];

  final lyrics = <LyricLine>[];
  final timestampRegex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');

  for (final line in lrc.split('\n')) {
    final matches = timestampRegex.allMatches(line);
    if (matches.isEmpty) continue;

    // Extract text by removing all timestamps
    final text = line.replaceAll(timestampRegex, '').trim();
    if (text.isEmpty) continue;

    // Add a line for each timestamp found using the cleaned text
    for (final match in matches) {
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final milliseconds = int.parse(
        match.group(3)!.padRight(3, '0').substring(0, 3),
      );

      lyrics.add(
        LyricLine(
          offset: Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: milliseconds,
          ),
          text: text,
        ),
      );
    }
  }

  lyrics.sort((a, b) => a.offset.compareTo(b.offset));
  return List.unmodifiable(lyrics);
}

/// 二分查找当前播放位置对应的歌词行，未开始时返回 -1。
int findCurrentLyricIndex(List<LyricLine> lyrics, Duration position) {
  var low = 0;
  var high = lyrics.length - 1;
  var answer = -1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    if (lyrics[mid].offset <= position) {
      answer = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return answer;
}
