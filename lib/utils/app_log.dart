import 'package:flutter/foundation.dart';

/// 统一日志入口：debug 才输出，避免 release 日志刷屏。
/// 调用方用 AppLog.d('...') 代替裸 debugPrint。
class AppLog {
  AppLog._();

  static void d(Object? message) {
    if (kDebugMode) debugPrint('$message');
  }
}
