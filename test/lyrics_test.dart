import 'package:flutter_test/flutter_test.dart';
import 'package:fysg_flutter/utils/lyrics.dart';

void main() {
  group('parseLyrics', () {
    test('returns empty list for null or empty input', () {
      expect(parseLyrics(null), isEmpty);
      expect(parseLyrics(''), isEmpty);
    });

    test('parses basic LRC format', () {
      final lyrics = parseLyrics('[00:01.00]hello\n[00:05.50]world');
      expect(lyrics.length, 2);
      expect(lyrics[0].text, 'hello');
      expect(lyrics[0].offset, const Duration(seconds: 1));
      expect(lyrics[1].text, 'world');
      // .50 -> 500ms
      expect(lyrics[1].offset, const Duration(seconds: 5, milliseconds: 500));
    });

    test('sorts lines by time', () {
      final lyrics = parseLyrics('[00:10.00]later\n[00:02.00]earlier');
      expect(lyrics.first.text, 'earlier');
      expect(lyrics.last.text, 'later');
    });

    test('expands multiple timestamps on one line', () {
      final lyrics = parseLyrics('[00:01.00][00:03.00]chorus');
      expect(lyrics.length, 2);
      expect(lyrics[0].offset, const Duration(seconds: 1));
      expect(lyrics[1].offset, const Duration(seconds: 3));
      expect(lyrics[0].text, 'chorus');
    });

    test('skips metadata tags and empty text lines', () {
      final lyrics = parseLyrics(
        '[ti:title]\n[ar:artist]\n[00:01.00]\n[00:02.00]real',
      );
      expect(lyrics.length, 1);
      expect(lyrics[0].text, 'real');
    });

    test('handles 2-digit milliseconds by padding', () {
      final lyrics = parseLyrics('[00:01.50]x');
      expect(
        lyrics.single.offset,
        const Duration(seconds: 1, milliseconds: 500),
      );
    });
  });

  group('parseLyricsCached', () {
    tearDown(clearLyricsCache);

    test('相同内容命中缓存返回同一实例', () {
      final first = parseLyricsCached(1, '[00:01.00]a');
      final second = parseLyricsCached(1, '[00:01.00]a');
      expect(identical(first, second), isTrue);
      expect(second.single.text, 'a');
    });

    test('歌词内容变化自动重算', () {
      final first = parseLyricsCached(2, '[00:01.00]a');
      final second = parseLyricsCached(2, '[00:02.00]b');
      expect(identical(first, second), isFalse);
      expect(second.single.text, 'b');
      expect(second.single.offset, const Duration(seconds: 2));
    });

    test('缓存有界：超过上限后最旧条目被淘汰', () {
      final original = parseLyricsCached(0, '[00:01.00]line0');
      for (var i = 1; i <= 35; i++) {
        parseLyricsCached(i, '[00:01.00]line$i');
      }
      final reparsed = parseLyricsCached(0, '[00:01.00]line0');
      // 已淘汰 → 重新解析出新的实例
      expect(identical(original, reparsed), isFalse);
      expect(reparsed.single.text, 'line0');
    });
  });

  group('findCurrentLyricIndex', () {
    final lyrics = parseLyrics('[00:10.00]a\n[00:20.00]b\n[00:30.00]c');

    test('returns -1 before first line starts', () {
      expect(findCurrentLyricIndex(lyrics, Duration.zero), -1);
      expect(findCurrentLyricIndex(lyrics, const Duration(seconds: 9)), -1);
    });

    test('finds the active line', () {
      expect(findCurrentLyricIndex(lyrics, const Duration(seconds: 10)), 0);
      expect(
        findCurrentLyricIndex(
          lyrics,
          const Duration(seconds: 19, milliseconds: 999),
        ),
        0,
      );
      expect(findCurrentLyricIndex(lyrics, const Duration(seconds: 20)), 1);
      expect(findCurrentLyricIndex(lyrics, const Duration(minutes: 1)), 2);
    });

    test('returns -1 for empty lyrics', () {
      expect(findCurrentLyricIndex(const [], Duration.zero), -1);
    });
  });
}
