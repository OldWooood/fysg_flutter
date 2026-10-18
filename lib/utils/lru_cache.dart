import 'dart:collection';

/// 通用有界 LRU 缓存：命中即刷新顺序，超出上限淘汰最久未使用。
///
/// 之前项目里多处手写「Map + 重排」的有界缓存（player 的歌曲详情缓存甚至
/// 只重排、不淘汰，长会话下无界增长），统一到这里，避免各处语义漂移。
class LruCache<K, V> {
  LruCache({this.maxEntries = 128}) : assert(maxEntries > 0);

  final int maxEntries;
  final LinkedHashMap<K, V> _entries = LinkedHashMap<K, V>();

  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;
  bool containsKey(K key) => _entries.containsKey(key);

  /// 读取并把该键移到最近使用位置。
  V? get(K key) {
    final value = _entries.remove(key);
    if (value == null) return null;
    _entries[key] = value;
    return value;
  }

  /// 写入并淘汰最久未使用的条目。
  void put(K key, V value) {
    _entries.remove(key);
    _entries[key] = value;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void remove(K key) => _entries.remove(key);

  void clear() => _entries.clear();
}
