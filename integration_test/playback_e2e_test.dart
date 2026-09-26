import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fysg_flutter/audio/app_audio_handler.dart';
import 'package:fysg_flutter/main.dart';
import 'package:fysg_flutter/providers/player_provider.dart';
import 'package:fysg_flutter/providers/shared_preferences_provider.dart';
import 'package:fysg_flutter/ui/common/song_list_tile.dart';
import 'package:fysg_flutter/ui/home/home_page.dart';

/// 真机 E2E：宿主编排（见下方 MARKER）。
/// 1. 测内点播第一首 -> 打印 E2E_CHECKPOINT_PLAYING
/// 2. 宿主 `adb shell input keyevent 87`（系统 NEXT）-> 测内观察到切歌，打印 NEXT
/// 3. 宿主 85（PLAY_PAUSE）-> 暂停，打印 PAUSED
/// 4. 宿主 85 -> 恢复，打印 RESUMED
/// 5. 测内直调 handler.skipToPrevious（与系统回调同一入口）
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) return;
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('E2E playback + system media keys', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await AppAudioService.init().timeout(const Duration(seconds: 15));
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MyApp(hasPrefs: true),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    final firstTile = find.descendant(
      of: find.byType(HomePage),
      matching: find.byType(SongListTile),
    );
    await _pumpUntil(
      tester,
      () => firstTile.evaluate().isNotEmpty,
      timeout: const Duration(seconds: 60),
    );
    expect(firstTile, findsWidgets);

    await tester.ensureVisible(firstTile.first);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(firstTile.first);
    await _pumpUntil(
      tester,
      () => container.read(playerProvider).isPlaying,
      timeout: const Duration(seconds: 30),
    );
    expect(container.read(playerProvider).isPlaying, isTrue);
    final firstId = container.read(playerProvider).currentSong?.id;
    expect(firstId, isNotNull);
    debugPrint('E2E_CHECKPOINT_PLAYING id=$firstId');

    await _pumpUntil(
      tester,
      () => container.read(playerProvider).currentSong?.id != firstId,
      timeout: const Duration(seconds: 40),
    );
    final secondId = container.read(playerProvider).currentSong?.id;
    debugPrint('E2E_CHECKPOINT_NEXT id=$secondId');
    expect(secondId, isNotNull);
    expect(secondId, isNot(firstId));

    await _pumpUntil(
      tester,
      () => !container.read(playerProvider).isPlaying,
      timeout: const Duration(seconds: 40),
    );
    debugPrint('E2E_CHECKPOINT_PAUSED');

    await _pumpUntil(
      tester,
      () => container.read(playerProvider).isPlaying,
      timeout: const Duration(seconds: 40),
    );
    debugPrint('E2E_CHECKPOINT_RESUMED');

    await AppAudioService.handler?.skipToPrevious();
    await tester.pump(const Duration(seconds: 3));
    debugPrint(
      'E2E_DONE id=${container.read(playerProvider).currentSong?.id}',
    );
  });
}
