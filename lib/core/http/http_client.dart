import 'dart:io';

import 'package:dio/dio.dart';

/// عميل شبكة واحد لكل التطبيق: مهلات معقولة، ترويسة تعريف، وإعادة محاولة
/// محدودة للأخطاء العابرة فقط.
class HttpClient {
  HttpClient({String? userAgent})
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 15),
            headers: {
              'User-Agent': userAgent ?? 'Maktaba/0.1 (offline manga reader)',
              'Accept': 'application/json',
            },
            responseType: ResponseType.json,
            validateStatus: (code) => code != null && code < 400,
          ),
        );

  final Dio _dio;

  Dio get raw => _dio;

  static const _maxAttempts = 3;

  Future<Response<T>> get<T>(
    String url, {
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) {
    return _withRetry(() => _dio.get<T>(
          url,
          queryParameters: query,
          options: options,
          cancelToken: cancelToken,
          onReceiveProgress: onReceiveProgress,
        ));
  }

  /// جلب صفحة HTML كنص، مع نفس سياسة إعادة المحاولة المستخدمة للـJSON.
  Future<Response<String>> getText(
    String url, {
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
  }) {
    final merged = (options ?? Options()).copyWith(
      responseType: ResponseType.plain,
      headers: {
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        ...?options?.headers,
      },
    );
    return _withRetry(() => _dio.get<String>(
          url,
          queryParameters: query,
          options: merged,
          cancelToken: cancelToken,
        ));
  }

  /// تنزيل ملف إلى مسار محلي. يُستعمل لصور الصفحات والأغلفة.
  Future<void> download(
    String url,
    String savePath, {
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
    Map<String, String>? headers,
  }) {
    return _withRetry(() => _dio.download(
          url,
          savePath,
          cancelToken: cancelToken,
          onReceiveProgress: onReceiveProgress,
          options: Options(
            headers: headers,
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(minutes: 2),
          ),
        ));
  }

  Future<R> _withRetry<R>(Future<R> Function() action) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await action();
      } on DioException catch (e) {
        final retryable = _isRetryable(e);
        if (!retryable || attempt >= _maxAttempts) rethrow;
        // تراجع أُسّي بسيط: 0.8s ثم 1.6s
        await Future<void>.delayed(Duration(milliseconds: 800 * attempt));
      }
    }
  }

  bool _isRetryable(DioException e) {
    if (e.type == DioExceptionType.cancel) return false;
    if (e.error is SocketException) return true;
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.connectionError =>
        true,
      DioExceptionType.badResponse => (e.response?.statusCode ?? 0) >= 500 ||
          e.response?.statusCode == 429,
      _ => false,
    };
  }

  void close() => _dio.close(force: true);
}
