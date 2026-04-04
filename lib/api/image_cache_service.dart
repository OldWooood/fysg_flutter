import '../utils/constants.dart';

class ImageCacheService {
  ImageCacheService._();

  static final Map<String, String> headers = {
    ...AppConstants.defaultHeaders,
    'Sec-Fetch-Dest': 'image',
    'Sec-Fetch-Mode': 'no-cors',
    'Sec-Fetch-Site': 'cross-site',
  };
}
