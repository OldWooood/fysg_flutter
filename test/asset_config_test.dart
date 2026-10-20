import 'package:flutter_test/flutter_test.dart';
import 'package:fysg_flutter/api/asset_config.dart';
import 'package:fysg_flutter/models/playlist.dart';
import 'package:fysg_flutter/models/song.dart';
import 'package:fysg_flutter/utils/constants.dart';

void main() {
  group('AssetConfig.parseDomains', () {
    test('parses quoted names and values', () {
      final domains = AssetConfig.parseDomains([
        {
          'id': '1',
          'name': "'image-domain'",
          'value': "'https://sg-file.gooddaycoco.com'",
        },
        {
          'id': '2',
          'name': "'audio-domain'",
          'value': "'https://sg-file.gooddaycoco.com/song_high'",
        },
        {'id': '9', 'name': "'rank-open'", 'value': "'0'"},
      ]);
      expect(domains['image-domain'], 'https://sg-file.gooddaycoco.com');
      expect(
        domains['audio-domain'],
        'https://sg-file.gooddaycoco.com/song_high',
      );
      expect(domains.containsKey('rank-open'), isFalse);
    });

    test('applyDomains ignores non-http values', () {
      final beforeImage = AssetConfig.imageBase;
      AssetConfig.applyDomains({'image-domain': '', 'audio-domain': 'ftp://x'});
      expect(AssetConfig.imageBase, beforeImage);
    });
  });

  group('Song.fromJson asset bases', () {
    test('joins audio url with audioBase without duplication', () {
      final song = Song.fromJson(
        {
          'id': 1,
          'name': 'a',
          'url': '/x/y.mp3',
          'album': {'cover': '/images/c.jpg'},
        },
        assetBase: 'https://img.example.com',
        audioBase: 'https://img.example.com/song_high',
      );
      expect(song.url, 'https://img.example.com/song_high/x/y.mp3');
      expect(song.cover, 'https://img.example.com/images/c.jpg');
    });

    test('keeps /song_high-prefixed urls on image base', () {
      final song = Song.fromJson(
        {'id': 1, 'name': 'a', 'url': '/song_high/x.mp3'},
        assetBase: 'https://img.example.com',
        audioBase: 'https://img.example.com/song_high',
      );
      expect(song.url, 'https://img.example.com/song_high/x.mp3');
    });
  });

  group('AssetConfig manifest domain migration', () {
    tearDown(() {
      AssetConfig.imageBase = AppConstants.assetBaseUrl;
      AssetConfig.audioBase = '${AppConstants.assetBaseUrl}/song_high';
    });

    test(
      'Song.fromManifest & Playlist.fromManifest migrate legacy CDN domains',
      () {
        AssetConfig.imageBase = 'https://cdn-new.example.com';
        AssetConfig.audioBase = 'https://cdn-new.example.com/song_high';

        final song = Song.fromManifest({
          'id': 10,
          'name': 'migrated',
          'cover': 'https://sg-file.nanqiao.xyz/images/cover.jpg',
          'url': 'https://sg-file.nanqiao.xyz/song_high/2024/a.mp3',
        });
        expect(song.cover, 'https://cdn-new.example.com/images/cover.jpg');
        expect(song.url, 'https://cdn-new.example.com/song_high/2024/a.mp3');

        final playlist = Playlist.fromManifest({
          'id': 20,
          'name': 'pl',
          'cover': 'https://sg-file.nanqiao.xyz/gepu/p.jpg',
          'type': 'playlist',
        });
        expect(playlist.cover, 'https://cdn-new.example.com/gepu/p.jpg');
      },
    );

    test('leaves unrelated external URLs untouched', () {
      final song = Song.fromManifest({
        'id': 1,
        'name': 's',
        'url': 'https://example.test/1.mp3',
      });
      expect(song.url, 'https://example.test/1.mp3');
    });
  });
}
