import 'package:flutter_test/flutter_test.dart';
import 'package:fysg_flutter/models/song.dart';

void main() {
  group('Song equality', () {
    test('equal songs compare by value', () {
      const a = Song(id: 1, name: 'n', artist: 'a');
      const b = Song(id: 1, name: 'n', artist: 'a');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different lyrics means different song', () {
      const a = Song(id: 1, name: 'n', lyrics: '[00:01]x');
      const b = Song(id: 1, name: 'n');
      expect(a == b, isFalse);
    });
  });

  group('Song.copyWith', () {
    test('keeps fields by default', () {
      const a = Song(id: 1, name: 'n', artist: 'a', lyrics: 'lrc');
      final b = a.copyWith();
      expect(b, equals(a));
    });

    test('nullable fields can be cleared', () {
      const a = Song(id: 1, name: 'n', artist: 'a');
      final b = a.copyWith(artist: () => null);
      expect(b.artist, isNull);
      expect(b.id, 1);
    });
  });

  group('Song.fromJson', () {
    test('dirty author/album shapes do not crash', () {
      final song = Song.fromJson({
        'songId': '7',
        'name': 't',
        'authors': 'not-a-list',
        'album': 'not-a-map',
        'url': '/x.mp3',
      });
      expect(song.id, 7);
      expect(song.artist, isNull);
    });

    test('relative audio url is prefixed with song_high', () {
      final song = Song.fromJson({
        'id': 3,
        'name': 't',
        'url': '/abc/x.mp3',
      });
      expect(song.url, contains('song_high'));
    });
  });
}
