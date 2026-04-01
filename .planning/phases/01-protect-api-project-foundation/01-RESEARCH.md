# Phase 1: Protect API + Project Foundation - Research

**Researched:** 2026-04-01
**Domain:** Flutter project scaffolding, Unifi Protect API authentication, secure credential storage, camera discovery
**Confidence:** HIGH

## Summary

Phase 1 is a greenfield Flutter project that establishes the app foundation: project structure, Protect API client (auth + camera discovery), secure credential persistence, and a UI for login and camera selection. The project must build and run on macOS desktop for rapid development iteration.

The critical technical challenges are: (1) Unifi Protect uses an undocumented, reverse-engineered API with cookie-based auth and CSRF tokens, (2) the Protect console uses self-signed SSL certificates that must be explicitly accepted, (3) flutter_secure_storage requires macOS Keychain Sharing entitlements to work on desktop, and (4) Riverpod has moved to 3.x with significant breaking changes from the 2.x API documented in CLAUDE.md.

**Primary recommendation:** Use flutter_riverpod 3.3.x (not 2.x), dio 5.9.x with a custom HttpClient for self-signed cert acceptance, flutter_secure_storage 10.x with macOS keychain entitlements, and go_router 17.x for declarative routing with auth-based redirects.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Simple single-screen form with Console IP, Username, and Password fields plus a Connect button. No wizard or multi-step flow.
- **D-02:** Self-signed SSL certificates get a one-time warning on first connection. User accepts once, app remembers the choice.
- **D-03:** Login errors displayed inline under the relevant field (e.g. "Connection refused" under IP, "Invalid credentials" under password). Standard Material error pattern.
- **D-04:** Checkbox list showing all discovered cameras. User selects 1 or 2 cameras (not strictly 2 -- flexible for when one camera is offline or being moved).
- **D-05:** Each camera row shows name + online/offline status from Protect API.
- **D-06:** "Start Monitoring" button enabled when 1-2 cameras are checked, disabled otherwise.
- **D-07:** On launch with saved credentials, auto-connect silently in the background. Show camera list once connected. If auth fails, fall back to login form with error message.
- **D-08:** Remember which cameras were last selected. On launch, auto-connect and go straight to monitoring view -- zero taps to resume overnight listening.
- **D-09:** Feature-first folder organization: `lib/features/auth/`, `lib/features/cameras/`, `lib/features/monitoring/`. Each feature has its own screens/, providers/, models/ subdirectories.
- **D-10:** Shared code in `lib/core/` -- API client, secure storage, router.
- **D-11:** Single `ProtectApiClient` class handling auth, bootstrap, and camera discovery. The API surface is ~3 endpoints; no need to split into separate service classes.

### Claude's Discretion
- Navigation/routing approach (go_router vs manual Navigator)
- Riverpod provider structure details
- Specific Dio interceptor implementation for auth token management
- Flutter project configuration (build settings, platform targets)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| AUTH-01 | User can authenticate with Unifi Protect console using IP address and credentials | Protect API login endpoint documented; Dio with self-signed cert handling; CSRF token flow researched |
| AUTH-02 | User can discover and select 2 cameras from Protect API camera list | Bootstrap endpoint returns cameras array with id, name, isConnected, channels with rtspAlias; data model documented |
| AUTH-03 | App persists credentials securely and auto-connects on launch | flutter_secure_storage 10.x with macOS Keychain Sharing entitlements; auto-connect flow via Riverpod async providers |
| PLAT-01 | App builds and runs on macOS desktop for development and rapid iteration | Flutter 3.35.3 available with macOS desktop support; macOS entitlements for keychain and network access documented |

</phase_requirements>

## Standard Stack

### Core (Phase 1 Only)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| flutter | 3.35.3 | App framework | Installed locally, exceeds minimum 3.22.0 requirement |
| dart | 3.9.2 | Language | Installed locally, exceeds minimum 3.4.0 requirement |
| flutter_riverpod | ^3.3.1 | State management | Current stable; Riverpod 3.x, NOT 2.x as CLAUDE.md states |
| dio | ^5.9.2 | HTTP client for Protect API | Self-signed cert support via IOHttpClientAdapter, interceptors for cookie/CSRF management |
| flutter_secure_storage | ^10.0.0 | Credential persistence | Keychain on macOS, Keystore on Android; v10 is a major update from v9.2 in CLAUDE.md |
| go_router | ^17.1.0 | Declarative routing | Auth-based redirects, clean URL structure, official Flutter team package |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| riverpod_annotation | ^3.1.0 | Code generation annotations | Provider declarations with @riverpod |
| riverpod_generator | (dev) | Code generator for providers | Build runner generates provider boilerplate |
| build_runner | (dev) | Dart code generation runner | Required by riverpod_generator |
| riverpod_lint | (dev) | Lint rules for Riverpod | Catch common Riverpod mistakes |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| go_router | Manual Navigator | go_router provides declarative auth redirects out of the box; manual Navigator requires more boilerplate for auth guards |
| Riverpod code generation | Manual provider declarations | Code gen reduces boilerplate; manual works fine for an app this size; recommend code gen for consistency |

### Version Corrections from CLAUDE.md

CLAUDE.md references outdated package versions. The planner MUST use these current versions:

| Package | CLAUDE.md Version | Current Version | Breaking Changes |
|---------|-------------------|-----------------|------------------|
| flutter_riverpod | ^2.6+ | ^3.3.1 | Ref lost type parameter; StateProvider/StateNotifierProvider are legacy; Notifiers recreated on rebuild; == filtering on all providers |
| flutter_secure_storage | ^9.2+ | ^10.0.0 | Android min SDK raised to 23; EncryptedSharedPreferences deprecated; macOS/iOS merged into flutter_secure_storage_darwin |
| dio | ^5.7+ | ^5.9.2 | No breaking changes, minor version bump |

**Installation:**
```bash
flutter create rtsp_audio_mixer --platforms=macos,android
cd rtsp_audio_mixer

# Core dependencies
flutter pub add flutter_riverpod dio flutter_secure_storage go_router

# Code generation (optional but recommended)
flutter pub add riverpod_annotation
flutter pub add -d riverpod_generator build_runner riverpod_lint custom_lint
```

## Architecture Patterns

### Recommended Project Structure

Per D-09 and D-10, feature-first organization:

```
lib/
├── main.dart                    # App entry, ProviderScope
├── app.dart                     # MaterialApp.router with GoRouter
├── core/
│   ├── api/
│   │   ├── protect_api_client.dart    # Single API client class (D-11)
│   │   └── dio_client.dart            # Dio factory with self-signed cert config
│   ├── storage/
│   │   └── secure_storage_service.dart # flutter_secure_storage wrapper
│   ├── router/
│   │   └── app_router.dart            # GoRouter config with auth redirect
│   └── models/
│       └── app_error.dart             # Shared error types
├── features/
│   ├── auth/
│   │   ├── screens/
│   │   │   └── login_screen.dart      # IP + username + password form (D-01)
│   │   ├── providers/
│   │   │   └── auth_provider.dart     # Auth state, auto-connect logic
│   │   └── models/
│   │       └── auth_state.dart        # Credentials, connection status
│   ├── cameras/
│   │   ├── screens/
│   │   │   └── camera_list_screen.dart # Checkbox list with online status (D-04, D-05)
│   │   ├── providers/
│   │   │   └── camera_provider.dart   # Camera list, selection state
│   │   └── models/
│   │       ├── protect_camera.dart    # Camera data model
│   │       └── stream_channel.dart    # RTSP channel info
│   └── monitoring/
│       └── screens/
│           └── monitoring_screen.dart  # Placeholder for Phase 2
└── test/
    ├── core/
    │   └── api/
    │       └── protect_api_client_test.dart
    └── features/
        └── auth/
            └── auth_provider_test.dart
```

### Pattern 1: Protect API Authentication Flow

**What:** Cookie-based auth with CSRF token, referencing hjdhjd/unifi-protect TypeScript implementation.
**When to use:** Every API call to the Protect console.

```dart
// Source: https://github.com/hjdhjd/unifi-protect/blob/main/src/protect-api.ts
class ProtectApiClient {
  final Dio _dio;
  String? _csrfToken;
  String? _cookie;

  /// Login to Protect console.
  /// POST /api/auth/login
  /// Body: { "username": "...", "password": "...", "rememberMe": true, "token": "" }
  /// Response headers: X-Updated-CSRF-Token (or X-CSRF-Token), Set-Cookie
  Future<bool> login(String host, String username, String password) async {
    final response = await _dio.post(
      'https://$host/api/auth/login',
      data: {
        'username': username,
        'password': password,
        'rememberMe': true,
        'token': '',
      },
    );

    // Extract CSRF token from response headers
    _csrfToken = response.headers.value('x-updated-csrf-token')
        ?? response.headers.value('x-csrf-token');

    // Extract cookie (only token portion before ";")
    final setCookie = response.headers.value('set-cookie');
    if (setCookie != null) {
      _cookie = setCookie.split(';').first;
    }

    return response.statusCode == 200;
  }

  /// Fetch bootstrap data (cameras, NVR info).
  /// GET /proxy/protect/api/bootstrap
  Future<ProtectBootstrap> getBootstrap(String host) async {
    final response = await _dio.get(
      'https://$host/proxy/protect/api/bootstrap',
      options: Options(headers: _authHeaders()),
    );
    return ProtectBootstrap.fromJson(response.data);
  }

  Map<String, String> _authHeaders() => {
    if (_csrfToken != null) 'x-csrf-token': _csrfToken!,
    if (_cookie != null) 'cookie': _cookie!,
  };
}
```

### Pattern 2: Self-Signed Certificate Handling (D-02)

**What:** Accept Unifi Protect's self-signed certificates with user consent.
**When to use:** Dio client creation for all Protect API calls.

```dart
// Source: https://api.flutter.dev/flutter/dart-io/HttpClient/badCertificateCallback.html
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

Dio createProtectDio({required bool acceptSelfSigned}) {
  final dio = Dio();

  if (acceptSelfSigned) {
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
      return client;
    };
  }

  return dio;
}
```

For D-02 (remember user's choice), store the acceptance flag in flutter_secure_storage alongside credentials.

### Pattern 3: Riverpod 3.x Auth State with Auto-Connect (D-07)

**What:** Async provider that checks for saved credentials on launch and auto-connects.
**When to use:** App initialization.

```dart
// Riverpod 3.x pattern -- Ref has no type parameter, use Notifier for state
@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  Future<AuthState> build() async {
    // On build, check for saved credentials and auto-connect
    final storage = ref.read(secureStorageProvider);
    final savedHost = await storage.read(key: 'protect_host');
    final savedUser = await storage.read(key: 'protect_username');
    final savedPass = await storage.read(key: 'protect_password');

    if (savedHost != null && savedUser != null && savedPass != null) {
      try {
        final client = ref.read(protectApiClientProvider);
        final success = await client.login(savedHost, savedUser, savedPass);
        if (success) {
          return AuthState.authenticated(host: savedHost);
        }
      } catch (e) {
        // Auto-connect failed, fall back to login form
      }
    }
    return AuthState.unauthenticated();
  }

  Future<void> login(String host, String username, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final client = ref.read(protectApiClientProvider);
      final success = await client.login(host, username, password);
      if (!success) throw Exception('Invalid credentials');

      // Persist credentials
      final storage = ref.read(secureStorageProvider);
      await storage.write(key: 'protect_host', value: host);
      await storage.write(key: 'protect_username', value: username);
      await storage.write(key: 'protect_password', value: password);

      return AuthState.authenticated(host: host);
    });
  }
}
```

### Pattern 4: GoRouter with Auth Redirect

**What:** Declarative routing that redirects to login when not authenticated.
**When to use:** App-level navigation.

```dart
@riverpod
GoRouter appRouter(Ref ref) {
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: '/cameras',
    redirect: (context, state) {
      final isAuthenticated = authState.valueOrNull?.isAuthenticated ?? false;
      final isLoggingIn = state.matchedLocation == '/login';

      if (!isAuthenticated && !isLoggingIn) return '/login';
      if (isAuthenticated && isLoggingIn) return '/cameras';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/cameras', builder: (_, __) => const CameraListScreen()),
      GoRoute(path: '/monitoring', builder: (_, __) => const MonitoringScreen()),
    ],
  );
}
```

### Anti-Patterns to Avoid

- **Hardcoding RTSP URL format:** Always derive RTSP URLs from bootstrap data. The URL pattern may change across firmware versions.
- **Storing credentials in SharedPreferences:** Use flutter_secure_storage exclusively. SharedPreferences is plaintext on Android.
- **Using Riverpod 2.x patterns:** StateProvider and StateNotifierProvider are legacy in 3.x. Use @riverpod annotated Notifiers.
- **Ignoring CSRF tokens:** The Protect API requires CSRF tokens for all authenticated requests. Missing them causes silent 403s.
- **Not handling cookie extraction properly:** The Set-Cookie header contains metadata after ";". Only the token portion before the first ";" should be stored.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Routing with auth guards | Custom Navigator observer + auth check | go_router with redirect | Built-in redirect logic, handles deep links, maintained by Flutter team |
| Secure credential storage | Custom encryption + file storage | flutter_secure_storage | Uses platform-native keystores (Keychain/Keystore), battle-tested |
| HTTP cookie management | Manual header manipulation | Dio interceptors | Dio's interceptor chain handles cookie persistence and CSRF token injection cleanly |
| Form validation | Custom validation logic | Flutter's built-in Form/TextFormField validators | Standard Material pattern, matches D-03 inline error display |

**Key insight:** This phase is mostly standard Flutter patterns (forms, HTTP, routing, state). The only novel part is the Protect API's undocumented auth flow. Don't over-engineer the foundation.

## Common Pitfalls

### Pitfall 1: flutter_secure_storage Silently Fails on macOS Without Keychain Entitlements

**What goes wrong:** Credentials appear to save but are never actually written. The app "forgets" login every restart.
**Why it happens:** flutter_secure_storage v10 on macOS requires Keychain Sharing capability in both DebugProfile.entitlements and Release.entitlements. Without it, writes silently succeed but reads return null.
**How to avoid:** Add to both `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:
```xml
<key>keychain-access-groups</key>
<array>
  <string>$(AppIdentifierPrefix)com.example.rtspAudioMixer</string>
</array>
```
**Warning signs:** `read()` always returns null even after successful `write()`. No errors thrown.

### Pitfall 2: Protect API CSRF Token Must Be Fetched Before First Login

**What goes wrong:** Login POST returns 403. The developer assumes wrong credentials when the actual issue is a missing CSRF token.
**Why it happens:** The Protect API may require a CSRF token even for the initial login. The hjdhjd/unifi-protect reference implementation fetches the base URL first to acquire an initial X-CSRF-Token header, then retries login with it.
**How to avoid:** If login returns 403 with no CSRF token present, GET the base URL (`https://{host}/`) to acquire the initial CSRF token from response headers, then retry login.
**Warning signs:** Login works in browser/curl but fails from the app with 403.

### Pitfall 3: Protect API Returns Massive Bootstrap JSON

**What goes wrong:** The bootstrap endpoint returns the entire NVR state, which can be 1-5MB of JSON for systems with many cameras and historical data. Parsing this synchronously blocks the main isolate and causes jank.
**Why it happens:** The bootstrap response includes every device, user, and setting on the NVR.
**How to avoid:** Parse bootstrap in a background isolate using `compute()` or Dart's `Isolate.run()`. Extract only the camera array and relevant fields into lightweight Dart models. Do not store the full bootstrap response.
**Warning signs:** UI freezes for 1-3 seconds after login while "loading cameras."

### Pitfall 4: Self-Signed Cert Acceptance Applies Globally

**What goes wrong:** Setting `badCertificateCallback` to always return true disables SSL validation for ALL requests from that HttpClient, not just Protect API calls.
**Why it happens:** `badCertificateCallback` is set on the HttpClient instance level.
**How to avoid:** Create a dedicated Dio instance for Protect API calls with self-signed cert acceptance. Use a separate Dio instance (or the default) for any other HTTPS calls. Optionally, pin the specific certificate on first connection rather than blanket-accepting all certs.
**Warning signs:** Security audit flags the app for disabled SSL validation.

### Pitfall 5: Riverpod 3.x Notifiers Are Recreated on Rebuild

**What goes wrong:** State stored in Notifier fields is lost unexpectedly because Riverpod 3.x creates fresh Notifier instances on every rebuild (unlike 2.x pseudo-singleton behavior).
**Why it happens:** Breaking change in Riverpod 3.0 -- Notifiers are no longer singletons.
**How to avoid:** Do not store long-lived state in Notifier instance fields. Use the provider's state property for all managed state. For resources like timers or controllers, split them into separate providers and use `ref.onDispose` for cleanup.
**Warning signs:** State resets unexpectedly when navigating between screens or when parent providers rebuild.

## Code Examples

### Camera Data Model (from Protect API bootstrap)

```dart
// Source: https://github.com/hjdhjd/unifi-protect/blob/main/src/protect-types.ts
class ProtectCamera {
  final String id;
  final String? name;
  final String type;        // e.g., "UVC G4 Dome"
  final String state;       // e.g., "CONNECTED", "DISCONNECTED"
  final bool isConnected;
  final List<StreamChannel> channels;

  const ProtectCamera({
    required this.id,
    this.name,
    required this.type,
    required this.state,
    required this.isConnected,
    required this.channels,
  });

  /// Construct RTSP URL for audio-only streaming (used by Phase 2)
  String? rtspUrl(String nvrHost, {bool encrypted = false}) {
    final channel = channels.firstWhere(
      (c) => c.isRtspEnabled,
      orElse: () => channels.first,
    );
    if (!channel.isRtspEnabled) return null;

    return encrypted
        ? 'rtsps://$nvrHost:7441/${channel.rtspAlias}?enableSrtp'
        : 'rtsp://$nvrHost:7447/${channel.rtspAlias}';
  }

  factory ProtectCamera.fromJson(Map<String, dynamic> json) {
    return ProtectCamera(
      id: json['id'] as String,
      name: json['name'] as String?,
      type: json['type'] as String,
      state: json['state'] as String,
      isConnected: json['isConnected'] as bool? ?? false,
      channels: (json['channels'] as List<dynamic>)
          .map((c) => StreamChannel.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

class StreamChannel {
  final int id;
  final String name;
  final String rtspAlias;
  final bool isRtspEnabled;

  const StreamChannel({
    required this.id,
    required this.name,
    required this.rtspAlias,
    required this.isRtspEnabled,
  });

  factory StreamChannel.fromJson(Map<String, dynamic> json) {
    return StreamChannel(
      id: json['id'] as int,
      name: json['name'] as String,
      rtspAlias: json['rtspAlias'] as String? ?? '',
      isRtspEnabled: json['isRtspEnabled'] as bool? ?? false,
    );
  }
}
```

### macOS Entitlements for Network + Keychain

```xml
<!-- macos/Runner/DebugProfile.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
  <key>keychain-access-groups</key>
  <array>
    <string>$(AppIdentifierPrefix)com.example.rtspAudioMixer</string>
  </array>
</dict>
</plist>
```

### Dio Interceptor for Protect Auth Headers

```dart
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
    // Capture updated CSRF token
    final newCsrf = response.headers.value('x-updated-csrf-token')
        ?? response.headers.value('x-csrf-token');
    if (newCsrf != null) csrfToken = newCsrf;

    // Capture cookie
    final setCookie = response.headers.value('set-cookie');
    if (setCookie != null) {
      cookie = setCookie.split(';').first;
    }

    handler.next(response);
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Riverpod 2.x StateProvider / StateNotifierProvider | Riverpod 3.x @riverpod annotated Notifiers | September 2025 | All provider patterns in CLAUDE.md need updating to 3.x style |
| flutter_secure_storage 9.x with EncryptedSharedPreferences | flutter_secure_storage 10.x with new cipher defaults | ~January 2026 | Android min SDK raised to 23; EncryptedSharedPreferences deprecated |
| Protect API cookie-only auth | Cookie auth + potential API key auth (X-API-KEY header) | Protect firmware updates | Must support both methods for forward compatibility |

**Deprecated/outdated:**
- StateProvider, StateNotifierProvider, ChangeNotifierProvider: Legacy in Riverpod 3.x, replaced by @riverpod Notifiers
- flutter_secure_storage EncryptedSharedPreferences option: Deprecated in v10 due to Jetpack Crypto discontinuation

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | Everything | Yes | 3.35.3 | -- |
| Dart SDK | Everything | Yes | 3.9.2 | -- |
| macOS desktop support | PLAT-01 | Yes (just enabled) | -- | -- |
| Xcode / macOS build tools | macOS desktop build | Assumed yes (macOS host) | -- | -- |
| Network access to Protect console | AUTH-01, AUTH-02 | LAN dependent | -- | Mock API for development |

**Missing dependencies with no fallback:** None

**Missing dependencies with fallback:** None -- all tools available locally.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (built-in) + mockito for mocking |
| Config file | None -- Wave 0 must create test structure |
| Quick run command | `flutter test test/core/` |
| Full suite command | `flutter test` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AUTH-01 | Protect API login with correct/incorrect credentials | unit | `flutter test test/core/api/protect_api_client_test.dart -x` | No -- Wave 0 |
| AUTH-01 | Self-signed cert acceptance flow | unit | `flutter test test/core/api/dio_client_test.dart -x` | No -- Wave 0 |
| AUTH-02 | Bootstrap parsing extracts camera list correctly | unit | `flutter test test/features/cameras/camera_model_test.dart -x` | No -- Wave 0 |
| AUTH-02 | Camera selection limited to 1-2 cameras | unit | `flutter test test/features/cameras/camera_provider_test.dart -x` | No -- Wave 0 |
| AUTH-03 | Credentials persist and load on restart | unit | `flutter test test/core/storage/secure_storage_test.dart -x` | No -- Wave 0 |
| AUTH-03 | Auto-connect with saved credentials | unit | `flutter test test/features/auth/auth_provider_test.dart -x` | No -- Wave 0 |
| PLAT-01 | App builds on macOS | smoke | `flutter build macos --debug` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `flutter test`
- **Per wave merge:** `flutter test` + `flutter build macos --debug`
- **Phase gate:** Full suite green + successful macOS build before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/core/api/protect_api_client_test.dart` -- covers AUTH-01 (login), AUTH-02 (bootstrap)
- [ ] `test/features/cameras/camera_model_test.dart` -- covers AUTH-02 (model parsing)
- [ ] `test/features/auth/auth_provider_test.dart` -- covers AUTH-03 (auto-connect)
- [ ] `pubspec.yaml` with mockito + build_runner dev dependencies
- [ ] Bootstrap JSON fixture file for deterministic test data

## Open Questions

1. **Protect API CSRF token bootstrap requirement**
   - What we know: The hjdhjd reference implementation fetches base URL first if no CSRF token is present, then retries login
   - What's unclear: Whether all Protect firmware versions require this two-step flow, or if some accept login without prior CSRF
   - Recommendation: Implement the two-step flow defensively (fetch base URL -> get CSRF -> login). It works for both cases.

2. **Protect API rate limiting on login**
   - What we know: The pitfalls research mentions 429 on `/api/auth/login` during reconnection storms
   - What's unclear: Exact rate limits (requests per minute) and lockout duration
   - Recommendation: Cap login retries to 3 attempts, then require manual user action. For auto-connect on launch, single attempt + fallback to login form.

3. **macOS network entitlements for HTTPS**
   - What we know: `com.apple.security.network.client` is needed in macOS entitlements for outgoing network connections
   - What's unclear: Whether Flutter's `flutter create` sets this by default for macOS
   - Recommendation: Verify after project creation, add if missing.

## Sources

### Primary (HIGH confidence)
- [hjdhjd/unifi-protect source - protect-api.ts](https://github.com/hjdhjd/unifi-protect/blob/main/src/protect-api.ts) -- Auth flow, CSRF token handling, bootstrap endpoint
- [hjdhjd/unifi-protect source - protect-types.ts](https://github.com/hjdhjd/unifi-protect/blob/main/src/protect-types.ts) -- Camera data model, bootstrap structure
- [Flutter badCertificateCallback API](https://api.flutter.dev/flutter/dart-io/HttpClient/badCertificateCallback.html) -- Self-signed cert handling
- [pub.dev: flutter_riverpod 3.3.1](https://pub.dev/packages/flutter_riverpod) -- Current version verified
- [pub.dev: dio 5.9.2](https://pub.dev/packages/dio) -- Current version verified
- [pub.dev: flutter_secure_storage 10.0.0](https://pub.dev/packages/flutter_secure_storage) -- Current version, breaking changes documented
- [pub.dev: go_router 17.1.0](https://pub.dev/packages/go_router) -- Current version verified
- [Riverpod 3.0 migration guide](https://riverpod.dev/docs/3.0_migration) -- Breaking changes from 2.x

### Secondary (MEDIUM confidence)
- [flutter_secure_storage GitHub README](https://github.com/juliansteenbakker/flutter_secure_storage/blob/develop/README.md) -- macOS keychain entitlements setup
- [Riverpod 3.0 community analysis](https://medium.com/@lee645521797/flutter-riverpod-3-0-released-a-major-redesign-of-the-state-management-framework-f7e31f19b179) -- Detailed 3.0 breaking changes

### Tertiary (LOW confidence)
- Protect API rate limiting behavior -- inferred from community reports, not officially documented

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all packages verified on pub.dev, versions confirmed
- Architecture: HIGH -- standard Flutter patterns, feature-first structure is well-established
- Protect API auth flow: MEDIUM -- reverse-engineered API, but reference implementation is actively maintained
- Pitfalls: HIGH -- based on verified platform documentation and library changelogs

**Research date:** 2026-04-01
**Valid until:** 2026-05-01 (stable domain, 30-day validity)
