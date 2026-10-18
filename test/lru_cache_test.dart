import 'package:flutter_test/flutter_test.dart';
import 'package:fysg_flutter/utils/lru_cache.dart';

void main() {
  test('基本读写', () {
    final cache = LruCache<int, String>(maxEntries: 2);
    cache.put(1, 'a');
    expect(cache.get(1), 'a');
    expect(cache.get(2), isNull);
    expect(cache.length, 1);
    expect(cache.containsKey(1), isTrue);
  });

  test('超过上限淘汰最久未使用', () {
    final cache = LruCache<int, String>(maxEntries: 2);
    cache.put(1, 'a');
    cache.put(2, 'b');
    cache.put(3, 'c');
    expect(cache.get(1), isNull);
    expect(cache.get(2), 'b');
    expect(cache.get(3), 'c');
    expect(cache.length, 2);
  });

  test('get 命中刷新 LRU 顺序', () {
    final cache = LruCache<int, String>(maxEntries: 2);
    cache.put(1, 'a');
    cache.put(2, 'b');
    cache.get(1); // 1 变为最近使用
    cache.put(3, 'c'); // 淘汰 2
    expect(cache.get(2), isNull);
    expect(cache.get(1), 'a');
    expect(cache.containsKey(3), isTrue);
  });

  test('覆盖写入不重复占位', () {
    final cache = LruCache<int, String>(maxEntries: 2);
    cache.put(1, 'a');
    cache.put(1, 'a2');
    cache.put(2, 'b');
    cache.put(3, 'c'); // 淘汰最旧的 1
    expect(cache.get(1), isNull);
    expect(cache.get(2), 'b');
    expect(cache.get(3), 'c');
  });

  test('remove/clear', () {
    final cache = LruCache<int, String>(maxEntries: 3);
    cache.put(1, 'a');
    cache.remove(1);
    expect(cache.get(1), isNull);
    cache.put(2, 'b');
    cache.clear();
    expect(cache.isEmpty, isTrue);
  });
}
