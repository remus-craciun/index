import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'interceptors.dart';
import 'token_store.dart';

/// Calls that work without a session, against an explicit server URL.
class PublicApi {
  PublicApi([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              contentType: Headers.jsonContentType,
            ));

  final Dio _dio;

  /// Verifies [serverUrl] runs this backend with a working database.
  Future<void> health(String serverUrl) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('$serverUrl/api/v1/health');
      if (res.data?['status'] != 'ok') {
        throw ApiException(code: 'unhealthy', message: 'The server is up but not healthy.');
      }
    } on DioException catch (e) {
      if (e.response != null && e.response!.data is! Map) {
        throw ApiException(code: 'not_index', message: "That address doesn't look like an Index server.");
      }
      throw ApiException.from(e);
    }
  }

  Future<bool> hasUser(String serverUrl) => _call(() async {
        final res = await _dio.get<Map<String, dynamic>>('$serverUrl/api/v1/auth/status');
        return res.data!['has_user'] as bool;
      });

  Future<AuthTokens> register(String serverUrl, String email, String password) => _call(() async {
        final res = await _dio.post<Map<String, dynamic>>('$serverUrl/api/v1/auth/register',
            data: {'email': email, 'password': password});
        return AuthTokens.fromJson(res.data!);
      });

  Future<AuthTokens> login(String serverUrl, String email, String password) => _call(() async {
        final res = await _dio.post<Map<String, dynamic>>('$serverUrl/api/v1/auth/login',
            data: {'email': email, 'password': password});
        return AuthTokens.fromJson(res.data!);
      });

  /// Ends the server-side session behind [refreshToken]. Best effort: a
  /// failure (e.g. offline) is ignored, since signing out must always work
  /// locally.
  Future<void> logout(String serverUrl, String refreshToken) async {
    try {
      await _dio.post<void>(
        '$serverUrl/api/v1/auth/logout',
        data: {'refresh_token': refreshToken},
        options: Options(sendTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 5)),
      );
    } catch (_) {}
  }

  /// Throws the raw [DioException] so the auth interceptor can inspect it.
  Future<AuthTokens> refresh(String serverUrl, String refreshToken) async {
    final res = await _dio.post<Map<String, dynamic>>('$serverUrl/api/v1/auth/refresh',
        data: {'refresh_token': refreshToken});
    return AuthTokens.fromJson(res.data!);
  }
}

/// Authenticated API bound to one server.
class Api {
  Api._(this._dio);

  factory Api.create({
    required String serverUrl,
    required TokenStore tokens,
    required PublicApi publicApi,
    required void Function() onSessionExpired,
  }) {
    final dio = Dio(BaseOptions(
      baseUrl: '$serverUrl/api/v1',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      contentType: Headers.jsonContentType,
    ));
    dio.interceptors.addAll([
      AuthInterceptor(
        dio: dio,
        tokens: tokens,
        refresh: (rt) => publicApi.refresh(serverUrl, rt),
        onSessionExpired: onSessionExpired,
      ),
      RetryInterceptor(dio: dio),
    ]);
    return Api._(dio);
  }

  /// For tests.
  factory Api.withDio(Dio dio) => Api._(dio);

  final Dio _dio;

  Future<Map<String, dynamic>> sync(Map<String, dynamic> body) => _call(() async {
        final res = await _dio.post<Map<String, dynamic>>('/sync', data: body);
        return res.data!;
      });

  /// Generates and stores a plan; returns it nested with milestones and tasks.
  Future<Map<String, dynamic>> decomposePlan({
    required String prompt,
    required String startDate,
    String? targetDate,
    required int minutesPerDay,
    int weekdays = 127,
  }) =>
      _call(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/ai/decompose-plan',
          data: {
            'prompt': prompt,
            'start_date': startDate,
            'target_date': ?targetDate,
            'minutes_per_day': minutesPerDay,
            'weekdays': weekdays,
          },
          options: Options(receiveTimeout: const Duration(seconds: 100)),
        );
        return res.data!;
      });

  /// Previews a follow-up request on a plan; returns
  /// `{revision, summary, changes, minutes_per_day}`. Nothing is stored.
  Future<Map<String, dynamic>> revisePlan({required String planId, required String instruction, required String today}) =>
      _call(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/ai/revise-plan',
          data: {'plan_id': planId, 'instruction': instruction, 'today': today},
          options: Options(receiveTimeout: const Duration(seconds: 100)),
        );
        return res.data!;
      });

  /// Stores a previewed revision; returns the updated plan, nested.
  Future<Map<String, dynamic>> applyRevision({
    required String planId,
    required Map<String, dynamic> revision,
    required String startDate,
    required int minutesPerDay,
  }) =>
      _call(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/plans/$planId/apply-revision',
          data: {'revision': revision, 'start_date': startDate, 'minutes_per_day': minutesPerDay},
        );
        return res.data!;
      });

  /// Replaces a task with subtasks; returns `{replaced_task_id, tasks}`.
  Future<Map<String, dynamic>> breakdownTask(String taskId) => _call(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/ai/breakdown-task',
          data: {'task_id': taskId},
          options: Options(receiveTimeout: const Duration(seconds: 100)),
        );
        return res.data!;
      });
}

Future<T> _call<T>(Future<T> Function() fn) async {
  try {
    return await fn();
  } catch (e) {
    throw ApiException.from(e);
  }
}
