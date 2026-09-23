import 'package:dio/dio.dart';

/// A failed API call, normalised from Dio errors and the server's
/// `{"error": {"code", "message"}}` envelope.
class ApiException implements Exception {
  ApiException({required this.code, required this.message, this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  /// True when the server could not be reached at all.
  bool get isNetwork => code == 'network';

  factory ApiException.from(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) {
      if (error.error is ApiException) return error.error! as ApiException;
      final data = error.response?.data;
      if (data is Map && data['error'] is Map) {
        final e = data['error'] as Map;
        return ApiException(
          code: '${e['code'] ?? 'error'}',
          message: '${e['message'] ?? 'Request failed'}',
          statusCode: error.response?.statusCode,
        );
      }
      switch (error.type) {
        case DioExceptionType.connectionError:
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return ApiException(code: 'network', message: "Can't reach the server. Check your connection.");
        case DioExceptionType.badCertificate:
          return ApiException(code: 'network', message: 'The server certificate is not trusted.');
        default:
          final status = error.response?.statusCode;
          return ApiException(
            code: 'http_$status',
            message: status == null ? 'Request failed' : 'Server returned HTTP $status',
            statusCode: status,
          );
      }
    }
    return ApiException(code: 'unknown', message: error.toString());
  }

  @override
  String toString() => message;
}
