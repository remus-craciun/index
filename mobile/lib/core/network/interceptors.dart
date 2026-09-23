import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

import 'token_store.dart';

/// Attaches the access token and transparently refreshes it once on 401.
/// Being a [QueuedInterceptor], concurrent 401s wait for a single refresh.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this.dio,
    required this.tokens,
    required this.refresh,
    required this.onSessionExpired,
  });

  final Dio dio;
  final TokenStore tokens;

  /// Exchanges a refresh token for a new pair; throws when rejected.
  final Future<AuthTokens> Function(String refreshToken) refresh;

  /// Called when the refresh token is rejected, so the app can log out.
  final void Function() onSessionExpired;

  static const _retriedKey = 'auth_retried';

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final t = await tokens.read();
    if (t != null) options.headers['Authorization'] = 'Bearer ${t.accessToken}';
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final req = err.requestOptions;
    if (err.response?.statusCode != 401 || req.extra[_retriedKey] == true) {
      return handler.next(err);
    }
    final current = await tokens.read();
    if (current == null) {
      onSessionExpired();
      return handler.next(err);
    }
    // Another queued request may already have refreshed the token.
    final sent = req.headers['Authorization'];
    var fresh = current;
    if (sent == 'Bearer ${current.accessToken}') {
      try {
        fresh = await refresh(current.refreshToken);
        await tokens.write(fresh);
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status == 401 || status == 403) {
          await tokens.clear();
          onSessionExpired();
        }
        return handler.next(err);
      }
    }
    req.extra[_retriedKey] = true;
    req.headers['Authorization'] = 'Bearer ${fresh.accessToken}';
    try {
      handler.resolve(await dio.fetch(req));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

/// Retries idempotent requests on network errors and 502/503/504 with
/// exponential backoff. `/sync` is safe to retry (last-write-wins upserts),
/// so it is treated as idempotent.
class RetryInterceptor extends Interceptor {
  RetryInterceptor({required this.dio, this.maxAttempts = 3});

  final Dio dio;
  final int maxAttempts;
  final _random = Random();

  static const _attemptKey = 'retry_attempt';

  bool _retryable(DioException e) {
    final method = e.requestOptions.method.toUpperCase();
    final idempotent = method == 'GET' || method == 'PUT' || method == 'DELETE' || method == 'PATCH' ||
        e.requestOptions.path.endsWith('/sync');
    if (!idempotent) return false;
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return true;
      case DioExceptionType.badResponse:
        final s = e.response?.statusCode ?? 0;
        return s == 502 || s == 503 || s == 504;
      default:
        return false;
    }
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final attempt = (err.requestOptions.extra[_attemptKey] as int?) ?? 1;
    if (attempt >= maxAttempts || !_retryable(err)) return handler.next(err);

    final delay = Duration(milliseconds: 400 * pow(2, attempt - 1).toInt() + _random.nextInt(250));
    await Future<void>.delayed(delay);
    err.requestOptions.extra[_attemptKey] = attempt + 1;
    try {
      handler.resolve(await dio.fetch(err.requestOptions));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
