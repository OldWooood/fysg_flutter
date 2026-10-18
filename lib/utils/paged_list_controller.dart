import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../api/fysg_service.dart' show PagedList;
import 'result.dart';

typedef PageFetcher<T> =
    Future<Result<PagedList<T>, AppError>> Function(int page);

/// 分页列表状态机：首页推荐 / 搜索结果 / 分类专辑歌单 / 歌单详情四处共用。
///
/// 之前 4 份手写实现行为不一致（搜索结果页刷新不重置页码、刷新失败顶掉已有
/// 列表、并发刷新与加载更多互相覆盖），这里统一：
/// - 刷新重置分页与状态；
/// - token 防竞态：后发请求作废先发响应，避免重复追加/错位；
/// - 已有数据时错误降级为 [onTransientError]（页面弹 toast），只有首屏
///   失败才整屏报错，不再因为一次刷新抖动清空列表。
/// 挂载/卸载方式：页面持有实例（`late final`），build 里用
/// `ListenableBuilder(listenable: controller, ...)` 订阅。
class PagedListController<T> extends ChangeNotifier {
  PagedListController({
    required this.fetch,
    this.transform,
    this.onTransientError,
  });

  final PageFetcher<T> fetch;

  /// 结果后处理（如搜索结果过滤不可播放项），同时作用于首屏与分页。
  final List<T> Function(List<T> items)? transform;

  /// 已有数据时的非致命错误（刷新失败/加载更多失败），由页面弹 toast。
  final void Function(AppError error)? onTransientError;

  final List<T> _items = [];
  int _page = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _loadMoreError = false;
  AppError? _error;
  int _token = 0;
  bool _disposed = false;

  /// 只读视图，避免页面直接改内部列表。
  UnmodifiableListView<T> get items => UnmodifiableListView(_items);
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  bool get loadMoreError => _loadMoreError;

  /// 仅当首屏失败（无数据可展示）时非空。
  AppError? get error => _error;

  List<T> _apply(List<T> items) => transform?.call(items) ?? items;

  Future<Result<PagedList<T>, AppError>> _fetchSafe(int page) async {
    try {
      return await fetch(page);
    } catch (e) {
      return Result.err(AppError.unknown(e));
    }
  }

  /// 首屏加载 / 下拉刷新。
  Future<void> refresh() async {
    if (_disposed) return;
    final token = ++_token;
    // 只在没有数据时才整屏 loading；下拉刷新交给 RefreshIndicator 自己转。
    _isLoading = _items.isEmpty;
    // 刷新作废在途的加载更多：同时复位其状态，避免 footer 转圈卡死。
    _isLoadingMore = false;
    _loadMoreError = false;
    _error = null;
    notifyListeners();

    final result = await _fetchSafe(0);
    if (_disposed || token != _token) return;

    result.when(
      ok: (paged) {
        _items
          ..clear()
          ..addAll(_apply(paged.items));
        _page = 0;
        _hasMore = paged.hasMore;
        _isLoading = false;
      },
      err: (e) {
        _isLoading = false;
        if (_items.isEmpty) {
          _error = e;
        } else {
          onTransientError?.call(e);
        }
      },
    );
    notifyListeners();
  }

  /// 触底加载下一页。
  Future<void> loadMore() async {
    if (_disposed || _isLoadingMore || _isLoading || !_hasMore) return;
    final token = ++_token;
    _isLoadingMore = true;
    _loadMoreError = false;
    notifyListeners();

    final nextPage = _page + 1;
    final result = await _fetchSafe(nextPage);
    if (_disposed || token != _token) return;

    result.when(
      ok: (paged) {
        _items.addAll(_apply(paged.items));
        _page = nextPage;
        _hasMore = paged.hasMore;
        _isLoadingMore = false;
      },
      err: (e) {
        _isLoadingMore = false;
        _loadMoreError = true;
        onTransientError?.call(e);
      },
    );
    notifyListeners();
  }

  /// 整屏错误页的「重试」：等价于刷新。
  Future<void> retry() => refresh();

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
