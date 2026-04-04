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

  factory AppError.network([String? message]) = NetworkError;
  factory AppError.cache([String? message]) = CacheError;
  factory AppError.notFound(String resource) = NotFoundError;
  factory AppError.unknown(Object error) = UnknownError;

  String get message => switch (this) {
    NetworkError(:final msg) => msg ?? '网络连接失败',
    CacheError(:final msg) => msg ?? '缓存操作失败',
    NotFoundError(:final resource) => '$resource 不存在',
    UnknownError(:final error) => '未知错误: $error',
  };
}

class NetworkError extends AppError {
  final String? msg;
  const NetworkError([this.msg]);
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
