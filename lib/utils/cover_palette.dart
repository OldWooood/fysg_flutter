import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../api/image_cache_service.dart';

/// 封面主色提取（替代已停更的 palette_generator）。
///
/// 流程：磁盘缓存取文件 -> isolate 内解码+直方图统计 -> 主色。
/// 调用方自行做 token 防串扰与 LRU（见 player_page）。
Future<Color?> extractCoverColor(String url) async {
  try {
    final file = await ImageCacheService.cacheManager.getSingleFile(
      url,
      headers: ImageCacheService.headers,
    );
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    return await compute(_dominantColor, bytes);
  } catch (_) {
    return null;
  }
}

/// isolate 入口：缩放到 48px，12bit 量化直方图，取最大簇均值。
/// 低饱和/极暗/极亮像素降权，避免渐变背景发灰。
Color? _dominantColor(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final thumb = img.copyResize(decoded, width: 48, height: 48);
    final buckets = <int, List<int>>{};
    for (var y = 0; y < thumb.height; y++) {
      for (var x = 0; x < thumb.width; x++) {
        final pixel = thumb.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
        final minC = r < g ? (r < b ? r : b) : (g < b ? g : b);
        // 跳过近黑/近白/低饱和，权重让给有色彩的像素
        if (maxC < 24 || minC > 232) continue;
        if (maxC - minC < 18) continue;
        final key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
        (buckets[key] ??= [0, 0, 0, 0])[0]++;
        buckets[key]![1] += r;
        buckets[key]![2] += g;
        buckets[key]![3] += b;
      }
    }
    if (buckets.isEmpty) return null;
    var bestKey = buckets.keys.first;
    var bestCount = 0;
    for (final entry in buckets.entries) {
      if (entry.value[0] > bestCount) {
        bestCount = entry.value[0];
        bestKey = entry.key;
      }
    }
    final best = buckets[bestKey]!;
    final n = best[0];
    return Color.fromARGB(255, best[1] ~/ n, best[2] ~/ n, best[3] ~/ n);
  } catch (_) {
    return null;
  }
}
