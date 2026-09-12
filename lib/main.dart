import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio/app_audio_handler.dart';
import 'l10n/app_localizations.dart';
import 'providers/shared_preferences_provider.dart';
import 'providers/theme_provider.dart';
import 'ui/main_screen.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 先跑一个极轻的 Splash，避免 AudioService/SP 串行阻塞导致的黑屏。
  // 后台并行初始化，任一失败都允许降级进入只读浏览模式。
  runApp(const _BootSplash());

  SharedPreferences? prefs;
  String? bootError;
  try {
    prefs = await SharedPreferences.getInstance()
        .timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('Boot prefs failed (degraded mode): $e');
    bootError = '$e';
  }
  try {
    await AppAudioService.init().timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('Boot audio failed (degraded mode): $e');
    bootError = [bootError, '$e'].whereType<String>().join('; ');
  }

  runApp(
    ProviderScope(
      overrides: [
        if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MyApp(hasPrefs: prefs != null, bootError: bootError),
    ),
  );
}

class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.music_note, size: 64, color: Color(0xFF3949AB)),
              SizedBox(height: 16),
              CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

class MyApp extends ConsumerWidget {
  final bool hasPrefs;
  final String? bootError;
  const MyApp({super.key, required this.hasPrefs, this.bootError});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!hasPrefs) {
      // SP 不可用时的降级提示页（仍可重试；音频/列表走内存态）
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 12),
                  Text(bootError ?? 'init failed'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => main(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      home: const MainScreen(),
    );
  }
}
