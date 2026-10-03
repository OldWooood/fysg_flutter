import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_log.dart';
import '../utils/constants.dart';

/// 资源域名运行时配置。
///
/// 背景：封面/音频地址由 `assetBase + 相对路径` 拼出，之前写死
/// `sg-file.nanqiao.xyz`，服务端迁移 CDN 后该域名下线，
/// 表现为“列表文字正常、封面全挂、播放全挂”。
/// 现启动时拉取 `/api/app/config` 的 `image-domain` / `audio-domain`，
/// 并持久化，冷启动先用上次的好域名。
class AssetConfig {
  AssetConfig._();

  static String imageBase = AppConstants.assetBaseUrl;
  static String audioBase = '${AppConstants.assetBaseUrl}/song_high';

  static String _stripQuotes(String raw) {
    var s = raw.trim();
    if (s.length >= 2 && s.startsWith("'") && s.endsWith("'")) {
      s = s.substring(1, s.length - 1);
    }
    return s.trim().replaceAll(RegExp(r'/+$'), '');
  }

  /// 从 config 接口的 settings 列表提取域名（兼容 name/value 带单引号）。
  static Map<String, String> parseDomains(List<dynamic> settings) {
    final domains = <String, String>{};
    for (final item in settings) {
      if (item is! Map) continue;
      final name = _stripQuotes('${item['name'] ?? ''}');
      final value = _stripQuotes('${item['value'] ?? ''}');
      if (name.isEmpty || value.isEmpty) continue;
      if (name == 'image-domain' ||
          name == 'audio-domain' ||
          name == 'audio-download-domain') {
        domains[name] = value;
      }
    }
    return domains;
  }

  static void applyDomains(Map<String, String> domains) {
    final image = domains['image-domain'];
    if (image != null && image.startsWith('http')) {
      imageBase = image;
    }
    final audio = domains['audio-domain'];
    if (audio != null && audio.startsWith('http')) {
      audioBase = audio;
    }
  }

  static void loadFromPrefs(SharedPreferences prefs) {
    try {
      final image = prefs.getString(AppConstants.spImageDomainKey);
      if (image != null && image.startsWith('http')) {
        imageBase = image;
      }
      final audio = prefs.getString(AppConstants.spAudioDomainKey);
      if (audio != null && audio.startsWith('http')) {
        audioBase = audio;
      }
    } catch (e) {
      AppLog.d('AssetConfig loadFromPrefs failed: $e');
    }
  }

  static Future<void> saveToPrefs(SharedPreferences prefs) async {
    try {
      await prefs.setString(AppConstants.spImageDomainKey, imageBase);
      await prefs.setString(AppConstants.spAudioDomainKey, audioBase);
    } catch (e) {
      AppLog.d('AssetConfig saveToPrefs failed: $e');
    }
  }
}
