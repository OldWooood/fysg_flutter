import 'package:flutter_test/flutter_test.dart';
import 'package:fysg_flutter/providers/queue_expander.dart';
import 'package:fysg_flutter/providers/queue_persistence.dart';

void main() {
  group('decodeCachedQueueJson', () {
    test('parses file format and skips dirty entries', () {
      final songs = decodeCachedQueueJson(
        '[{"id":1,"name":"a"},"not-a-map",42,{"id":2,"name":"b"}]',
      );
      expect(songs.map((s) => s.id).toList(), [1, 2]);
    });

    test('returns empty on garbage', () {
      expect(decodeCachedQueueJson('{{{'), isEmpty);
      expect(decodeCachedQueueJson('{"a":1}'), isEmpty);
    });
  });

  group('decodeCachedQueue legacy', () {
    test('skips bad lines', () {
      final songs = decodeCachedQueue(['{"id":1,"name":"a"}', 'garbage']);
      expect(songs.length, 1);
      expect(songs.first.id, 1);
    });
  });

  group('QueueExpander.expandOrder', () {
    test('starts at current and alternates outward', () {
      final order = QueueExpander.expandOrder(5, 2);
      expect(order.first, 2);
      expect(order.toSet(), {0, 1, 2, 3, 4});
      expect(order.length, 5);
    });

    test('clamps out-of-range start', () {
      final order = QueueExpander.expandOrder(3, 99);
      expect(order.length, 3);
      expect(order.first, 2);
    });
  });
}
