import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fysg_flutter/api/fysg_service.dart';

/// 脚本化适配器：按调用序号返回预设响应，序号越界后重复最后一个。
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.steps);

  final List<FutureOr<ResponseBody> Function(RequestOptions options, int call)>
  steps;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final call = requests.length;
    requests.add(options);
    final step = steps[call < steps.length ? call : steps.length - 1];
    return step(options, call);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object data, {int statusCode = 200}) =>
    ResponseBody.fromString(
      jsonEncode(data),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

ResponseBody _songListBody() => _json({
  'code': 0,
  'data': {
    'list': [
      {'id': 1, 'name': 'Song A'},
    ],
    'count': 1,
  },
});

FysgService _service(_ScriptedAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.httpClientAdapter = adapter;
  return FysgService(dio: dio);
}

void main() {
  test('5xx 指数退避重试后成功', () async {
    final adapter = _ScriptedAdapter([
      (_, _) => _json({'code': 0}, statusCode: 500),
      (_, _) => _json({'code': 0}, statusCode: 500),
      (_, _) => _songListBody(),
    ]);
    final result = await _service(adapter).searchSongsPaged('a');

    expect(result.isOk, isTrue);
    expect(result.value!.items.single.name, 'Song A');
    expect(adapter.requests, hasLength(3)); // 1 次 + 2 次重试
  });

  test('全部 5xx 失败映射为 server 错误码', () async {
    final adapter = _ScriptedAdapter([
      (_, _) => _json({'code': 0}, statusCode: 503),
    ]);
    final result = await _service(adapter).searchSongsPaged('a');

    expect(result.isErr, isTrue);
    expect(result.error!.code, 'server');
    expect(adapter.requests, hasLength(3));
  });

  test('404 映射为 notFound 且不重试', () async {
    final adapter = _ScriptedAdapter([
      (_, _) => _json({'code': 1}, statusCode: 404),
    ]);
    final result = await _service(adapter).getSongDetails(42);

    expect(result.error!.code, 'notFound');
    expect(adapter.requests, hasLength(1));
  });

  test('429 映射为 rateLimited 且不重试', () async {
    final adapter = _ScriptedAdapter([
      (_, _) => _json({'code': 1}, statusCode: 429),
    ]);
    final result = await _service(adapter).searchSongsPaged('a');

    expect(result.error!.code, 'rateLimited');
    expect(adapter.requests, hasLength(1));
  });

  test('搜索缓存 TTL 内直接复用，不再发请求', () async {
    final adapter = _ScriptedAdapter([(_, _) => _songListBody()]);
    final service = _service(adapter);

    await service.searchSongsPaged('abc');
    final second = await service.searchSongsPaged('abc');

    expect(second.isOk, isTrue);
    expect(adapter.requests, hasLength(1));
  });

  test('并发相同详情请求合并为一次网络调用', () async {
    final adapter = _ScriptedAdapter([
      (_, _) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return _json({
          'code': 0,
          'data': {'id': 7, 'name': 'Detail'},
        });
      },
    ]);
    final service = _service(adapter);

    final results = await Future.wait([
      service.getSongDetails(7),
      service.getSongDetails(7),
    ]);

    expect(results.every((r) => r.isOk), isTrue);
    expect(results.first.value!.name, 'Detail');
    expect(adapter.requests, hasLength(1));
  });

  test('forceRefresh 绕过详情缓存', () async {
    final adapter = _ScriptedAdapter([
      (_, _) => _json({
        'code': 0,
        'data': {'id': 7, 'name': 'Detail'},
      }),
    ]);
    final service = _service(adapter);

    await service.getSongDetails(7);
    await service.getSongDetails(7, forceRefresh: true);

    expect(adapter.requests, hasLength(2));
  });

  test('取消搜索建议：返回 cancelled 且不再重试（取消链路回归）', () async {
    final adapter = _ScriptedAdapter([
      (_, _) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return _json({'code': 0, 'data': <Object>[]});
      },
    ]);
    final service = _service(adapter);
    final token = CancelToken();

    final future = service.getSearchSuggestions('abc', cancelToken: token);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    token.cancel('user typing');
    final result = await future;

    expect(result.isErr, isTrue);
    expect(result.error!.code, 'cancelled');
    expect(adapter.requests, hasLength(1));
  });
}
