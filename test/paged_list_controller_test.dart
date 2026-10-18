import 'package:flutter_test/flutter_test.dart';
import 'package:fysg_flutter/api/fysg_service.dart' show PagedList;
import 'package:fysg_flutter/utils/paged_list_controller.dart';
import 'package:fysg_flutter/utils/result.dart';

PagedList<int> _paged(int page, {int size = 20, int total = 45}) {
  final start = page * size;
  final end = (start + size).clamp(0, total);
  final items = start >= total
      ? const <int>[]
      : [for (var i = start; i < end; i++) i];
  return PagedList(items: items, total: total, page: page, size: size);
}

void main() {
  test('refresh 加载首页并给出 hasMore', () async {
    final calls = <int>[];
    final controller = PagedListController<int>(
      fetch: (page) async {
        calls.add(page);
        return Result.ok(_paged(page));
      },
    );
    expect(controller.isLoading, isTrue);
    await controller.refresh();
    expect(calls, [0]);
    expect(controller.items, hasLength(20));
    expect(controller.isLoading, isFalse);
    expect(controller.hasMore, isTrue);
    controller.dispose();
  });

  test('loadMore 追加到最后一页后 hasMore=false 且不再请求', () async {
    final calls = <int>[];
    final controller = PagedListController<int>(
      fetch: (page) async {
        calls.add(page);
        return Result.ok(_paged(page));
      },
    );
    await controller.refresh();
    await controller.loadMore();
    await controller.loadMore(); // 45 首：0/1/2 三页
    expect(controller.items, hasLength(45));
    expect(controller.hasMore, isFalse);
    await controller.loadMore();
    expect(calls, [0, 1, 2]);
    controller.dispose();
  });

  test('refresh 重置分页（回归：搜索结果页刷新后错位）', () async {
    final calls = <int>[];
    final controller = PagedListController<int>(
      fetch: (page) async {
        calls.add(page);
        return Result.ok(_paged(page));
      },
    );
    await controller.refresh();
    await controller.loadMore();
    await controller.refresh();
    await controller.loadMore();
    expect(calls, [0, 1, 0, 1]);
    expect(controller.items, hasLength(40));
    controller.dispose();
  });

  test('首屏失败给出 error，retry 成功后恢复', () async {
    var fail = true;
    final controller = PagedListController<int>(
      fetch: (page) async =>
          fail ? Result.err(NetworkError.timeout()) : Result.ok(_paged(page)),
    );
    await controller.refresh();
    expect(controller.error?.code, 'timeout');
    expect(controller.items, isEmpty);
    expect(controller.isLoading, isFalse);

    fail = false;
    await controller.retry();
    expect(controller.error, isNull);
    expect(controller.items, hasLength(20));
    controller.dispose();
  });

  test('已有数据时刷新失败：保留列表、不整屏报错、回调 transient', () async {
    var fail = false;
    final transient = <AppError>[];
    final controller = PagedListController<int>(
      fetch: (page) async =>
          fail ? Result.err(NetworkError.server(500)) : Result.ok(_paged(page)),
      onTransientError: transient.add,
    );
    await controller.refresh();
    fail = true;
    await controller.refresh();
    expect(controller.items, hasLength(20)); // 列表保留
    expect(controller.error, isNull); // 不整屏报错
    expect(transient.single.code, 'server');
    controller.dispose();
  });

  test('loadMore 失败置 footer 错误并可重试', () async {
    var failPage1 = true;
    final controller = PagedListController<int>(
      fetch: (page) async => page == 1 && failPage1
          ? Result.err(NetworkError.timeout())
          : Result.ok(_paged(page)),
    );
    await controller.refresh();
    await controller.loadMore();
    expect(controller.loadMoreError, isTrue);
    expect(controller.isLoadingMore, isFalse);
    expect(controller.items, hasLength(20));

    failPage1 = false;
    await controller.loadMore();
    expect(controller.loadMoreError, isFalse);
    expect(controller.items, hasLength(40));
    controller.dispose();
  });

  test('并发 loadMore 只发一次请求', () async {
    final calls = <int>[];
    final controller = PagedListController<int>(
      fetch: (page) async {
        calls.add(page);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return Result.ok(_paged(page));
      },
    );
    await controller.refresh();
    await Future.wait([controller.loadMore(), controller.loadMore()]);
    expect(calls, [0, 1]);
    expect(controller.items, hasLength(40));
    controller.dispose();
  });

  test('刷新作废在途 loadMore，不重复追加、footer 不卡死', () async {
    final controller = PagedListController<int>(
      fetch: (page) async {
        if (page == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        return Result.ok(_paged(page));
      },
    );
    await controller.refresh();
    final loadMore = controller.loadMore();
    final refresh = controller.refresh();
    await Future.wait([loadMore, refresh]);
    expect(controller.items, hasLength(20)); // 只保留刷新后的首页
    expect(controller.isLoadingMore, isFalse);
    controller.dispose();
  });

  test('transform 同时作用于首屏与分页', () async {
    final controller = PagedListController<int>(
      fetch: (page) async => Result.ok(_paged(page)),
      transform: (items) => items.where((i) => i.isEven).toList(),
    );
    await controller.refresh();
    expect(controller.items, hasLength(10)); // 0..19 中偶数
    expect(controller.items.first, 0);
    controller.dispose();
  });

  test('fetch 抛异常时转成 unknown 错误而不是崩溃', () async {
    final controller = PagedListController<int>(
      fetch: (page) => Future.error(StateError('boom')),
    );
    await controller.refresh();
    expect(controller.error?.code, 'unknown');
    controller.dispose();
  });
}
