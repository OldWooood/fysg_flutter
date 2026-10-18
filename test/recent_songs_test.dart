import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fysg_flutter/api/recently_played_service.dart';
import 'package:fysg_flutter/models/song.dart';
import 'package:fysg_flutter/providers/shared_preferences_provider.dart';
import 'package:fysg_flutter/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('RecentSongsNotifier：去重置顶，只有一份列表实例', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(recentSongsProvider.notifier);
    notifier.add(const Song(id: 1, name: 'a'));
    notifier.add(const Song(id: 2, name: 'b'));
    notifier.add(const Song(id: 1, name: 'a-new'));

    final list = container.read(recentSongsProvider);
    expect(list.map((s) => s.id), [1, 2]);
    expect(list.first.name, 'a-new');
  });

  test('RecentSongsNotifier：超过 500 条截断最旧', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(recentSongsProvider.notifier);
    for (var i = 0; i < 505; i++) {
      notifier.add(Song(id: i, name: 'song$i'));
    }

    final list = container.read(recentSongsProvider);
    expect(list, hasLength(RecentlyPlayedService.maxSongs));
    expect(list.first.id, 504);
    expect(list.map((s) => s.id), isNot(contains(0)));
  });

  test('snapshot 从磁盘恢复（脏数据跳过）', () async {
    SharedPreferences.setMockInitialValues({
      AppConstants.spRecentSongs: [
        json.encode({'id': 5, 'name': 'from-disk'}),
        'not-a-json-object',
      ],
    });
    final prefs = await SharedPreferences.getInstance();
    final service = RecentlyPlayedService(prefs);

    final songs = service.snapshot();
    expect(songs.single.id, 5);
    expect(songs.single.name, 'from-disk');
    service.dispose();
  });

  test('schedulePersist 防抖合并写入，快照去歌词', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = RecentlyPlayedService(
      prefs,
      persistDebounce: const Duration(milliseconds: 20),
    );
    addTearDown(service.dispose);

    service.schedulePersist([
      const Song(id: 1, name: 'a', lyrics: '[00:01.00]very long lrc'),
    ]);
    service.schedulePersist([const Song(id: 2, name: 'b')]);

    await Future<void>.delayed(const Duration(milliseconds: 60));

    final raw = prefs.getStringList(AppConstants.spRecentSongs);
    expect(raw, hasLength(1));
    expect(raw!.single, contains('"id":2'));
    expect(raw.single, isNot(contains('lrc')));
  });
}
