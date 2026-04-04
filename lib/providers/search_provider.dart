import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';

/// 搜索结果状态 Provider
final searchResultsProvider = StateProvider<List<Song>>((ref) => []);

/// 是否正在搜索状态 Provider
final isSearchingProvider = StateProvider<bool>((ref) => false);
