import 'package:flutter/foundation.dart';

/// 结果类型，用于替代异常处理
///
/// 使用示例:
/// ```dart
/// Future<Result<List<Song>, AppError>> searchSongs(String query) async {
///   try {
///     final songs = await _fetchSongs(query);
///     return Result.ok(songs);
///   } on NetworkException catch (e) {
///     return Result.err(AppError.network(e.message));
///   }
/// }
/// ```
sealed class Result<T, E> {
  const Result();

  factory Result.ok(T value) = Ok<T, E>;
  factory Result.err(E error) = Err<T, E>;

  bool get isOk => this is Ok<T, E>;
  bool get isErr => this is Err<T, E>;

  T? get value => isOk ? (this as Ok<T, E>)._value : null;
  E? get error => isErr ? (this as Err<T, E>)._error : null;

  R when<R>({
    required R Function(T value) ok,
    required R Function(E error) err,
  }) {
    return switch (this) {
      Ok<T, E>(:final _value) => ok(_value),
      Err<T, E>(:final _error) => err(_error),
    };
  }

  R? whenOk<R>(R Function(T value) fn) {
    if (isOk) return fn((this as Ok<T, E>)._value);
    return null;
  }

  R? whenErr<R>(R Function(E error) fn) {
    if (isErr) return fn((this as Err<T, E>)._error);
    return null;
  }

  T unwrapOr(T defaultValue) => value ?? defaultValue;

  T unwrap() {
    if (isOk) return (this as Ok<T, E>)._value;
    throw StateError('Called unwrap on Err: $error');
  }
}

@immutable
class Ok<T, E> extends Result<T, E> {
  final T _value;
  const Ok(this._value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Ok<T, E> &&
          runtimeType == other.runtimeType &&
          _value == other._value;

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => 'Ok($_value)';
}

@immutable
class Err<T, E> extends Result<T, E> {
  final E _error;
  const Err(this._error);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Err<T, E> &&
          runtimeType == other.runtimeType &&
          _error == other._error;

  @override
  int get hashCode => _error.hashCode;

  @override
  String toString() => 'Err($_error)';
}

/// 应用错误类型
sealed class AppError {
  const AppError();

  factory AppError.network([String? message, String code = 'network']) =>
      NetworkError(message, code);
  factory AppError.cache([String? message]) = CacheError;
  factory AppError.notFound(String resource) = NotFoundError;
  factory AppError.unknown(Object error) = UnknownError;

  /// 结构化错误码：UI 层据此做国际化映射，避免网络层硬编码中文解析
  String get code => switch (this) {
    NetworkError(:final errorCode) => errorCode,
    CacheError() => 'cache',
    NotFoundError() => 'notFound',
    UnknownError() => 'unknown',
  };

  String get message => switch (this) {
    NetworkError(:final msg) => msg ?? '网络连接失败',
    CacheError(:final msg) => msg ?? '缓存操作失败',
    NotFoundError(:final resource) => '$resource 不存在',
    UnknownError(:final error) => '未知错误: $error',
  };
}

class NetworkError extends AppError {
  final String? msg;
  final String errorCode;
  const NetworkError([this.msg, this.errorCode = 'network']);

  /// 便捷构造：语义明确的常用码，避免各处手写字符串
  factory NetworkError.timeout([String? msg]) =>
      NetworkError(msg ?? '请求超时，请检查网络后重试', 'timeout');
  factory NetworkError.rateLimited([String? msg]) =>
      NetworkError(msg ?? '请求过于频繁，请稍后重试', 'rateLimited');
  factory NetworkError.forbidden(int status) =>
      NetworkError('访问被拒绝($status)，请稍后重试', 'forbidden');
  factory NetworkError.server(int status) =>
      NetworkError('服务器错误: $status', 'server');
}

class CacheError extends AppError {
  final String? msg;
  const CacheError([this.msg]);
}

class NotFoundError extends AppError {
  final String resource;
  const NotFoundError(this.resource);
}

class UnknownError extends AppError {
  final Object error;
  const UnknownError(this.error);
}
