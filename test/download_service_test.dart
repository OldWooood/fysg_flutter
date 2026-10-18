import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fysg_flutter/api/download_service.dart';
import 'package:fysg_flutter/models/song.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

/// 返回固定字节 / 指定状态码的适配器。
class _BytesAdapter implements HttpClientAdapter {
  _BytesAdapter(this.body);

  final Uint8List body;
  int statusCode = 200;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    if (statusCode >= 400) {
      return ResponseBody.fromString('error', statusCode);
    }
    return ResponseBody.fromBytes(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['audio/mpeg'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Song _song(int id) =>
    Song(id: id, name: 'Song $id', url: 'https://example.test/$id.mp3');

void main() {
  late Directory tempRoot;
  late SharedPreferences prefs;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('fysg_download_test');
    PathProviderPlatform.instance = _FakePathProvider(tempRoot.path);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    try {
      await tempRoot.delete(recursive: true);
    } catch (_) {}
  });

  DownloadService buildService(HttpClientAdapter adapter) {
    final dio = Dio();
    dio.httpClientAdapter = adapter;
    return DownloadService(prefs, dio: dio);
  }

  test('downloadSong 原子落盘 + manifest + isDownloaded 内存索引', () async {
    final adapter = _BytesAdapter(Uint8List.fromList(List.filled(64, 7)));
    final service = buildService(adapter);

    await service.downloadSong(_song(1));

    expect(adapter.calls, 1);
    final file = await service.getLocalFile(1);
    expect(await file.exists(), isTrue);
    expect(await file.length(), 64);
    expect(
      await file.parent.list().any((e) => e.path.endsWith('.part')),
      isFalse,
    );

    expect(await service.isDownloaded(1), isTrue);
    final manifest = await service.getDownloadedSongs();
    expect(manifest.single.id, 1);
    expect(manifest.single.name, 'Song 1');
    service.dispose();
  });

  test('首轮 500 后重试成功，最终文件完整', () async {
    final adapter = _BytesAdapter(Uint8List.fromList(List.filled(32, 1)));
    adapter.statusCode = 500;
    final service = buildService(adapter);

    final future = service.downloadSong(_song(2));
    // 第一次失败后 1s 退避，再置成功
    Future<void>.delayed(const Duration(milliseconds: 200)).then((_) {
      adapter.statusCode = 200;
    });
    await future;

    expect(adapter.calls, 2);
    final file = await service.getLocalFile(2);
    expect(await file.length(), 32);
    service.dispose();
  });

  test('全部重试失败：抛出异常、清理 .part、不写 manifest', () async {
    final adapter = _BytesAdapter(Uint8List.fromList([1, 2, 3]));
    adapter.statusCode = 500;
    final service = buildService(adapter);

    await expectLater(
      service.downloadSong(_song(3)),
      throwsA(isA<Exception>()),
    );

    expect(adapter.calls, 3); // downloadMaxRetries
    final file = await service.getLocalFile(3);
    expect(await file.exists(), isFalse);
    expect(await File('${file.path}.part').exists(), isFalse);
    expect(await service.getDownloadedSongs(), isEmpty);
    service.dispose();
  });

  test('prefetch 已存在时跳过重复下载', () async {
    final adapter = _BytesAdapter(Uint8List.fromList(List.filled(16, 9)));
    final service = buildService(adapter);

    await service.prefetchSong(_song(4));
    await service.prefetchSong(_song(4));

    expect(adapter.calls, 1);
    expect(await service.isPrefetched(4), isTrue);
    expect(await service.listPrefetchedSongIds(), contains(4));
    service.dispose();
  });

  test('prefetch 超限时按最旧优先淘汰并同步索引', () async {
    final adapter = _BytesAdapter(Uint8List.fromList(List.filled(32, 5)));

    // 不同服务实例模拟"同一 App 会话内的多次预取"（复用同一目录）
    final s1 = buildService(adapter);
    await s1.prefetchSong(_song(10));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await s1.prefetchSong(_song(11));
    s1.dispose();

    // 第二首歌只增量为已知总量，不触发扫描（内部记账）；
    // 这里再用独立实例强制扫描 + 淘汰。
    final s2 = buildService(adapter);
    await s2.enforcePrefetchLimit(maxBytes: 40); // 只容得下 32 字节 → 淘汰最旧的 10

    final remaining = await s2.listPrefetchedSongIds();
    expect(remaining, {11});
    final old = await s2.getPrefetchFile(10);
    final fresh = await s2.getPrefetchFile(11);
    expect(await old.exists(), isFalse);
    expect(await fresh.exists(), isTrue);
    s2.dispose();
  });

  test('deleteDownload 只清目标条目', () async {
    final adapter = _BytesAdapter(Uint8List.fromList(List.filled(8, 3)));
    final service = buildService(adapter);

    await service.downloadSong(_song(1));
    await service.downloadSong(_song(2));
    await service.deleteDownload(1);

    final manifest = await service.getDownloadedSongs();
    expect(manifest.single.id, 2);
    expect(await service.isDownloaded(1), isFalse);
    service.dispose();
  });
}
