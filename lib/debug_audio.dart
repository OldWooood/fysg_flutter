import 'dart:io';
import 'package:http/http.dart' as http;
// import 'package:path_provider/path_provider.dart';

void main() async {
  // Use a known image URL or construct one
  // Assuming pattern based on audio: https://sg-file.nanqiao.xyz/blah/blah/blah.jpg
  // But wait, cover URLs come from API.
  // Let's rely on a known good or test one if available, but for now just test connectivity to base.
  
  const String imageUrl = 'https://sg-file.nanqiao.xyz/生命河灵粮堂/神机会的风/专辑封面.jpg'; // Hypothetical
  // Alternatively use the audio URL again just to test download logic as a proxy for image
  const String testUrl = 'https://sg-file.nanqiao.xyz/生命河灵粮堂/神机会的风/你的爱不离不弃.mp3';

  final Uri uri = Uri.parse(testUrl);
  print('Testing Download from: $uri');

  try {
    final headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Referer': 'https://www.fysg.org/',
    'Origin': 'https://www.fysg.org',
    'Accept': '*/*',
    'Sec-Fetch-Dest': 'audio',
    'Sec-Fetch-Mode': 'no-cors',
    'Sec-Fetch-Site': 'cross-site',
  };
    final response = await http.get(uri, headers: headers);
    
    print('Response Code: ${response.statusCode}');
    if (response.statusCode == 200) {
        print('Download successful. Length: ${response.bodyBytes.length}');
        // Verify we can write to a file
        // final tempDir = Directory.systemTemp;
        // final file = File('${tempDir.path}/test_download.mp3');
        // await file.writeAsBytes(response.bodyBytes);
        // print('Written to ${file.path}');
    } else {
        print('Failed to download: ${response.statusCode}');
    }
  } catch (e) {
    print('Error: $e');
  }
}
