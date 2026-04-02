import 'package:dio/dio.dart';

/// Dio interceptor that manages CSRF tokens and cookies for Protect API auth.
///
/// On each request, injects the current CSRF token and cookie headers.
/// On each response, extracts updated CSRF tokens and cookies.
class ProtectAuthInterceptor extends Interceptor {
  String? csrfToken;
  String? cookie;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (csrfToken != null) {
      options.headers['x-csrf-token'] = csrfToken;
    }
    if (cookie != null) {
      options.headers['cookie'] = cookie;
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final newCsrf = response.headers.value('x-updated-csrf-token') ??
        response.headers.value('x-csrf-token');
    if (newCsrf != null) csrfToken = newCsrf;

    final setCookie = response.headers.value('set-cookie');
    if (setCookie != null) {
      cookie = setCookie.split(';').first;
    }

    handler.next(response);
  }
}
