import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/download_service.dart';
import '../models/song.dart';

/// 已下载歌曲列表 Provider
final downloadedSongsProvider = FutureProvider.autoDispose<List<Song>>((
  ref,
) async {
  return ref.read(downloadServiceProvider).getDownloadedSongs();
});
