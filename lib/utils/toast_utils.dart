import 'package:flutter/material.dart';

import '../utils/result.dart';
import '../l10n/app_localizations.dart';

class ToastUtils {
  static void showToast(BuildContext context, String message) {
    _show(context, message, Colors.black87, Icons.info_outline);
  }

  static void showSuccess(BuildContext context, String message) {
    _show(context, message, Colors.green.shade700, Icons.check_circle_outline);
  }

  static void showError(BuildContext context, String message) {
    _show(context, message, Theme.of(context).colorScheme.error, Icons.error_outline);
  }

  /// AppError -> 本地化文案：网络层中文硬编码不再直达英文用户
  static void showAppError(BuildContext context, AppError error) {
    showError(context, localizedAppError(context, error));
  }

  static String localizedAppError(BuildContext context, AppError error) {
    final l10n = AppLocalizations.of(context);
    return switch (error.code) {
      'timeout' => l10n.errorTimeout,
      'rateLimited' => l10n.errorRateLimited,
      'forbidden' => l10n.errorForbidden,
      'server' => l10n.errorServer,
      'notFound' => l10n.errorNotFound(error.message),
      'cache' => l10n.errorCache,
      _ => l10n.errorNetwork,
    };
  }

  static void _show(
    BuildContext context,
    String message,
    Color background,
    IconData icon,
  ) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    // 之前写死 width:200，小屏/长文案溢出；改为按屏幕宽度自适应
    final screenWidth = MediaQuery.sizeOf(context).width;
    final toastWidth = (screenWidth - 64).clamp(120.0, 360.0);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
        width: toastWidth,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
