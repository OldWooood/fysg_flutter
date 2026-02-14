import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'fysg_service.dart';

class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._internal();

  factory ImageCacheService() {
    return _instance;
  }

  ImageCacheService._internal();

  static const Map<String, String> headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            'Referer': 'https://www.fysg.org/',
            'Origin': 'https://www.fysg.org',
            'Sec-Fetch-Dest': 'image',
            'Sec-Fetch-Mode': 'no-cors',
            'Sec-Fetch-Site': 'cross-site',
  };

  /// Downloads the image at [url] with FYSG headers and returns the local file path.
  /// If already cached, returns the local path immediately.
  Future<String?> getCachedImagePath(String url) async {
    try {
      final Directory cacheDir = await getTemporaryDirectory();
      // Simple filename generation: replace non-alphanumeric chars
      final String filename = url.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final File file = File('${cacheDir.path}/$filename');

      if (await file.exists()) {
        return file.path;
      }

      final response = await http.get(Uri.parse(url), headers: headers);

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return file.path;
      } else {
        print('Failed to download image: $url, status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error caching image: $e');
      return null;
    }
  }
}
