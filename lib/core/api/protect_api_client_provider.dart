import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dio_client.dart';
import 'protect_api_client.dart';
import 'protect_auth_interceptor.dart';

/// Provider for the Protect API client.
///
/// Creates a Dio instance with self-signed cert acceptance (D-02)
/// and attaches the auth interceptor for CSRF/cookie management.
final protectApiClientProvider = Provider<ProtectApiClient>((ref) {
  final dio = createProtectDio(acceptSelfSigned: true);
  final interceptor = ProtectAuthInterceptor();
  return ProtectApiClient(dio: dio, authInterceptor: interceptor);
});
