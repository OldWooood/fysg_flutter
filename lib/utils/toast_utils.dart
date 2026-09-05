import 'package:flutter/material.dart';

class ToastUtils {
  static void showToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    // 之前写死 width:200，小屏/长文案溢出；改为按屏幕宽度自适应
    final screenWidth = MediaQuery.sizeOf(context).width;
    final toastWidth = (screenWidth - 64).clamp(120.0, 360.0);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.black87,
        behavior: SnackBarBehavior.floating,
        width: toastWidth,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
