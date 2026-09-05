import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppTheme {
  static const _seedColor = Color(0xFF3949AB);

  // 之前是 getter，每次访问都 ColorScheme.fromSeed 重建；改为 static final 缓存
  static final ThemeData lightTheme = _baseTheme(
    ColorScheme.fromSeed(seedColor: _seedColor),
    Brightness.light,
  );

  static final ThemeData darkTheme = _baseTheme(
    ColorScheme.fromSeed(seedColor: _seedColor, brightness: Brightness.dark),
    Brightness.dark,
  );

  static ThemeData _baseTheme(ColorScheme colorScheme, Brightness brightness) {
    final onSurfaceHigh = brightness == Brightness.light
        ? Colors.black87
        : Colors.white70;
    final onSurfaceMedium = brightness == Brightness.light
        ? Colors.black54
        : Colors.white60;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? Colors.white
          : const Color(0xFF121212),

      // Typography（中文由系统字体渲染，仅调整字号/字重层级）
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 44,
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface,
        ),
        displayMedium: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: onSurfaceHigh),
        bodyMedium: TextStyle(fontSize: 14, color: onSurfaceMedium),
      ),

      // App Bar
      appBarTheme: AppBarTheme(
        backgroundColor: brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF121212),
        elevation: 0,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
