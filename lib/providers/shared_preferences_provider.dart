import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 全局实例 Provider
///
/// 在 main.dart 中通过 ProviderScope overrides 初始化:
/// ```dart
/// final prefs = await SharedPreferences.getInstance();
/// runApp(
///   ProviderScope(
///     overrides: [
///       sharedPreferencesProvider.overrideWithValue(prefs),
///     ],
///     child: MyApp(),
///   ),
/// );
/// ```
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'SharedPreferences 未初始化。请在 main.dart 中通过 overrides 注入实例。',
  );
});
