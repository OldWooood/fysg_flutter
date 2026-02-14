void main() {
  const urlParams = 'https://sg-file.nanqiao.xyz/生命河灵粮堂/神机会的风/你的爱不离不弃.mp3';
  final uri = Uri.parse(urlParams);
  print('Original: $urlParams');
  print('Parsed: $uri');
  print('Encoded Path: ${uri.path}');
  print('Is Absolute: ${uri.isAbsolute}');
  
  // Check if it matches what a browser might send
  print('ToString: ${uri.toString()}');
}
