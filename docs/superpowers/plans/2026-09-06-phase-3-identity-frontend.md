# Phase 3 — Identity & Authentication (Flutter): implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Phase 3 screens against the backend this phase's other plan delivers — Sign In, Register, Verify Email, Session expired, Account Settings with its sub-screens — each in every state the prototypes show, with token storage, silent refresh, and crash reporting behind an interface, so the frontend lines of §Phase 3's Done-when pass in `flutter test` and against the running dev server.

**Architecture:** Riverpod owns all state. `core/api` is a thin envelope-aware HTTP client that attaches the bearer token, refreshes once on `ACCESS_TOKEN_EXPIRED` through a single in-flight future, and surfaces every failure as a typed exception. `core/auth` holds tokens in secure storage and drives one `AuthState` the root widget switches on. `core/crash` is the `CrashReporter` seam over Sentry. Screens live in `features/auth` and `features/account`, use only Phase 1 tokens and shared widgets, and match `mockups/design-composer/{Sign In,Register,Verify Email,Account Settings,App States}.dc.html`.

**Tech Stack:** Flutter 3.47 · Dart 3.13 · `flutter_riverpod 3.4.3` · `http 1.6.0` · `flutter_secure_storage 11.0.0` · `device_info_plus 13.2.0` · `share_plus 13.3.0` · `sentry_flutter 9.29.0` · `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-06-phase-3-identity-design.md` (§8 is the frontend section; §3–§5 are the API contract this client speaks). The backend plan `docs/superpowers/plans/2026-09-06-phase-3-identity-backend.md` fixes the exact routes, bodies and error codes — read its Tasks 3–7 route blocks when a call's shape matters.

## Global Constraints

- `frontend/CLAUDE.md` governs: feature-based layout, Riverpod for anything outliving a widget, every screen with loading · empty · error · populated states, inline errors under their field, 48 dp targets, semantic labels, reduced-motion handling, no hardcoded colour/font/spacing/radius — tokens via `context.colors` / `context.type` / `context.motion`, geometry from `AppSpacing` / `AppRadius` / `AppSizes`. Every inset is `EdgeInsetsDirectional` (`test/core/rtl_lint_test.dart` fails the build otherwise).
- Every tappable thing is built on `Pressable`; `AppHeader` goes at the top of the body, never in `Scaffold.appBar`; a network-triggering button shows its **own** loading state (`AppButton(loading: true)`); loading content uses skeletons, not spinners.
- **No phone number is ever shown with a check mark, the word "verified", or any success marker.** No screen offers SMS, mentions a text message, or shows a phone icon beside a code entry. Copy for the verification code always says **email**.
- Copy is the prototypes' copy. Where the plan and a prototype disagree the plan wins and the divergence is flagged in the decision record: data export is handed to the share sheet (the prototype's "emailed within a day" is wrong); session rows show device name and last-used age only (no `· Malé`).
- Error handling routes on `code`, never on message text. Codes this client handles: `VALIDATION_FAILED` (details → field errors), `EMAIL_IN_USE`, `PHONE_IN_USE`, `INVALID_CREDENTIALS`, `EMAIL_NOT_VERIFIED`, `EMAIL_ALREADY_VERIFIED`, `EMAIL_UNCHANGED`, `OTP_EXPIRED`, `OTP_INCORRECT` (`details.attemptsRemaining`), `OTP_INVALIDATED`, `OTP_RATE_LIMITED` (`details.retryAfterSeconds`, `details.limit`), `SOCIAL_AUTH_UNAVAILABLE`, `ACCESS_TOKEN_EXPIRED`, `REFRESH_TOKEN_ROTATED`, `SESSION_EXPIRED`, `UNAUTHENTICATED`, `RATE_LIMITED`, `ACCOUNT_FROZEN`.
- Base URL from `--dart-define=API_BASE_URL` (default `http://localhost:3000`); Sentry from `--dart-define=SENTRY_DSN` (default empty → no-op reporter).
- Tests: real Inter and Material Icons via `test/flutter_test_config.dart`; never `pumpAndSettle` over a spinner or skeleton — pump two frames (`await tester.pump(); await tester.pump(const Duration(milliseconds: 400));`). Every screen test checks every state. The fake API client is the test seam; no test touches the network.
- `flutter analyze --no-pub` and `flutter test` clean before every commit; `dart format` runs in the pre-commit hook. Commits: no AI attribution, imperative summary, one per task, push at the end.
- Use `package:` imports only (`always_use_package_imports`); `prefer_single_quotes`; `require_trailing_commas`.

## File structure

```
frontend/lib/
  core/api/api_client.dart            ApiClient, ApiException, ApiNetworkException, envelope decoding (Task 1)
  core/api/api_config.dart            baseUrl from dart-define (Task 1)
  core/auth/token_store.dart          TokenStore interface + SecureTokenStore + InMemoryTokenStore (Task 2)
  core/auth/auth_models.dart          UserAccount, TokenPair, AuthState, VerificationOutcome, fromJson (Task 2)
  core/auth/auth_api.dart             AuthApi — typed calls to /v1/auth and /v1/users/me (Task 2)
  core/auth/auth_controller.dart      AuthController (Notifier<AuthState>), providers (Task 2)
  core/auth/form_draft_store.dart     FormDraftStore — restores typed input after session expiry (Task 2)
  core/auth/device_name.dart          deviceNameProvider via device_info_plus (Task 2)
  core/crash/crash_reporter.dart      CrashReporter, NoopCrashReporter, SentryCrashReporter (Task 3)
  main.dart                           ProviderScope, runZonedGuarded, crash reporter (Task 3)
  app.dart                            AuthGate root, route table (Task 7)
  features/auth/presentation/sign_in_screen.dart            (Task 4)
  features/auth/presentation/register_screen.dart           (Task 5)
  features/auth/presentation/verify_email_screen.dart       (Task 6)
  features/auth/presentation/widgets/otp_code_entry.dart    six boxes (Task 6)
  features/auth/presentation/widgets/countdown_text.dart    m:ss countdown driven by a clock (Task 6)
  features/auth/presentation/widgets/auth_hero.dart         the gradient header Sign In and Register share (Task 4)
  features/auth/presentation/widgets/social_sign_in_row.dart (Task 4)
  features/auth/presentation/session_expired_screen.dart    (Task 7)
  features/auth/controller/sign_in_controller.dart, register_controller.dart, verify_email_controller.dart
  features/account/presentation/account_settings_screen.dart      (Task 8)
  features/account/presentation/active_sessions_screen.dart       (Task 8)
  features/account/presentation/download_data_screen.dart         (Task 8)
  features/account/presentation/delete_account_screen.dart        confirm + frozen (Task 8)
  features/account/presentation/change_password_screen.dart       (Task 9)
  features/account/presentation/change_email_screen.dart          (Task 9)
  features/account/presentation/change_phone_screen.dart          (Task 9)
  features/account/presentation/widgets/settings_row.dart         (Task 8)
  features/account/controller/*.dart
frontend/test/
  helpers/fake_api.dart               FakeApiClient with scripted responses (Task 1)
  helpers/pump.dart                   pumpScreen(tester, widget, overrides) with ProviderScope + theme (Task 1)
  core/api/api_client_test.dart · core/auth/auth_controller_test.dart · core/crash/crash_reporter_test.dart
  features/auth/*_test.dart · features/account/*_test.dart · features/auth/phone_never_verified_test.dart
```

---

### Task 1: Dependencies, `ApiClient`, and the test seams

**Files:**
- Modify: `frontend/pubspec.yaml`
- Create: `frontend/lib/core/api/api_config.dart`, `frontend/lib/core/api/api_client.dart`
- Create: `frontend/test/helpers/fake_api.dart`, `frontend/test/helpers/pump.dart`
- Test: `frontend/test/core/api/api_client_test.dart`

**Interfaces:**
- Produces:
  - `ApiConfig.baseUrl` (String, from `String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:3000')`).
  - `abstract class ApiClient { Future<Map<String, dynamic>> get(String path); Future<Map<String, dynamic>> post(String path, {Object? body, Map<String, String>? headers}); Future<Map<String, dynamic>> patch(String path, {Object? body}); Future<Map<String, dynamic>> delete(String path); }` — every method returns the envelope's `data` (a Map, or `{'_list': [...]}` when `data` is a list — see below) and throws `ApiException` or `ApiNetworkException`.
  - `class ApiException implements Exception { final int status; final String code; final String message; final Object? details; List<FieldError> get fieldErrors; int? get retryAfterSeconds; int? get attemptsRemaining; String? get limit; }`, `class FieldError { final String path; final String message; }`, `class ApiNetworkException implements Exception {}`.
  - `class HttpApiClient implements ApiClient` with constructor `HttpApiClient({required http.Client http, required String baseUrl, required Future<String?> Function() readAccessToken, required Future<bool> Function() refreshTokens, required Future<void> Function() onSessionExpired})`.
  - Test: `FakeApiClient` (queue of `(method, path) → response | exception`), `pumpScreen`.

- [ ] **Step 1: Dependencies**

Edit `frontend/pubspec.yaml` `dependencies:`

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^3.4.3
  http: ^1.6.0
  flutter_secure_storage: ^11.0.0
  device_info_plus: ^13.2.0
  share_plus: ^13.3.0
  sentry_flutter: ^9.29.0
```

Run `cd frontend && flutter pub get`.

- [ ] **Step 2: Failing tests**

`frontend/test/core/api/api_client_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:raajjepro/core/api/api_client.dart';

void main() {
  http.Client scripted(List<http.Response Function(http.Request)> handlers) {
    var i = 0;
    return MockClient((request) async {
      final handler = handlers[i < handlers.length ? i : handlers.length - 1];
      i += 1;
      return handler(request);
    });
  }

  http.Response ok(Object data, {int status = 200}) => http.Response(jsonEncode({'data': data}), status, headers: {'content-type': 'application/json'});
  http.Response err(int status, String code, {Object? details}) => http.Response(
        jsonEncode({'error': {'code': code, 'message': 'm', if (details != null) 'details': details}, 'requestId': 'r'}),
        status,
        headers: {'content-type': 'application/json'},
      );

  HttpApiClient client(http.Client http, {Future<bool> Function()? refresh, Future<void> Function()? expired, String? token = 't1'}) => HttpApiClient(
        http: http,
        baseUrl: 'http://api.test',
        readAccessToken: () async => token,
        refreshTokens: refresh ?? () async => false,
        onSessionExpired: expired ?? () async {},
      );

  test('attaches the bearer token and unwraps the envelope', () async {
    late http.Request seen;
    final c = client(MockClient((r) async { seen = r; return ok({'id': 'u1'}); }));
    final data = await c.get('/v1/auth/me');
    expect(data['id'], 'u1');
    expect(seen.headers['authorization'], 'Bearer t1');
    expect(seen.url.toString(), 'http://api.test/v1/auth/me');
  });

  test('an error envelope becomes an ApiException routed on code, with typed details', () async {
    final c = client(scripted([(_) => err(409, 'EMAIL_IN_USE', details: [{'path': 'email', 'message': 'taken'}])]));
    try {
      await c.post('/v1/auth/register', body: {});
      fail('expected ApiException');
    } on ApiException catch (e) {
      expect(e.status, 409);
      expect(e.code, 'EMAIL_IN_USE');
      expect(e.fieldErrors.single.path, 'email');
    }
    final rl = client(scripted([(_) => err(429, 'OTP_RATE_LIMITED', details: {'retryAfterSeconds': 272, 'limit': 'address'})]));
    final e = await rl.post('/x').then<ApiException?>((_) => null, onError: (Object e) => e as ApiException);
    expect(e?.retryAfterSeconds, 272);
    expect(e?.limit, 'address');
  });

  test('ACCESS_TOKEN_EXPIRED refreshes once and retries; ten parallel calls cause one refresh', () async {
    var refreshes = 0;
    var calls = 0;
    final c = client(
      MockClient((r) async {
        calls += 1;
        return r.headers['authorization'] == 'Bearer t2' ? ok({'ok': true}) : err(401, 'ACCESS_TOKEN_EXPIRED');
      }),
      refresh: () async { refreshes += 1; await Future<void>.delayed(const Duration(milliseconds: 20)); return true; },
    );
    var current = 't1';
    c.readAccessToken = () async => current;
    c.afterRefresh = () { current = 't2'; };
    final results = await Future.wait(List.generate(10, (_) => c.get('/v1/auth/me')));
    expect(results.every((r) => r['ok'] == true), isTrue);
    expect(refreshes, 1);
    expect(calls, 20);
  });

  test('a failed refresh, or SESSION_EXPIRED, calls onSessionExpired and throws the code', () async {
    var expired = 0;
    final c = client(scripted([(_) => err(401, 'SESSION_EXPIRED')]), expired: () async { expired += 1; });
    await expectLater(c.get('/x'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'SESSION_EXPIRED')));
    expect(expired, 1);
    final f = client(scripted([(_) => err(401, 'ACCESS_TOKEN_EXPIRED')]), refresh: () async => false, expired: () async { expired += 1; });
    await expectLater(f.get('/x'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'SESSION_EXPIRED')));
    expect(expired, 2);
  });

  test('a socket failure is ApiNetworkException, never a raw message', () async {
    final c = client(MockClient((_) async => throw http.ClientException('boom')));
    await expectLater(c.get('/x'), throwsA(isA<ApiNetworkException>()));
  });

  test('a list payload is wrapped so callers always get a map', () async {
    final c = client(scripted([(_) => ok([{'id': 's1'}])]));
    final data = await c.get('/v1/auth/sessions');
    expect((data['_list'] as List).length, 1);
  });
}
```

- [ ] **Step 3: Run to fail** — `cd frontend && flutter test test/core/api/api_client_test.dart` — Expected: FAIL (missing files).

- [ ] **Step 4: `api_config.dart`**

```dart
/// Where the API lives. Set with `--dart-define=API_BASE_URL=https://…`;
/// the default reaches a dev server on the same machine (an Android emulator
/// wants `http://10.0.2.2:3000`, passed the same way).
abstract final class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );
}
```

- [ ] **Step 5: `api_client.dart`**

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// One field-level problem from a `VALIDATION_FAILED`, `EMAIL_IN_USE` or
/// `PHONE_IN_USE` response: the client renders it under its field.
class FieldError {
  const FieldError({required this.path, required this.message});
  final String path;
  final String message;
}

/// The API said no. Routed on [code] — never on [message], which is for
/// display only (backend/CLAUDE.md: codes are the contract).
class ApiException implements Exception {
  ApiException({
    required this.status,
    required this.code,
    required this.message,
    this.details,
  });

  final int status;
  final String code;
  final String message;
  final Object? details;

  List<FieldError> get fieldErrors {
    final d = details;
    if (d is! List) return const [];
    return d
        .whereType<Map<String, dynamic>>()
        .map(
          (m) => FieldError(
            path: m['path'] as String? ?? '',
            message: m['message'] as String? ?? '',
          ),
        )
        .toList();
  }

  int? _detailInt(String key) {
    final d = details;
    return d is Map<String, dynamic> ? (d[key] as num?)?.toInt() : null;
  }

  String? _detailString(String key) {
    final d = details;
    return d is Map<String, dynamic> ? d[key] as String? : null;
  }

  int? get retryAfterSeconds => _detailInt('retryAfterSeconds');
  int? get attemptsRemaining => _detailInt('attemptsRemaining');
  String? get limit => _detailString('limit');

  @override
  String toString() => 'ApiException($status $code)';
}

/// The request never got an answer: no connection, DNS, timeout. Screens
/// render their offline state; nothing shows the underlying message.
class ApiNetworkException implements Exception {
  const ApiNetworkException();
}

abstract class ApiClient {
  Future<Map<String, dynamic>> get(String path);
  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Map<String, String>? headers,
  });
  Future<Map<String, dynamic>> patch(String path, {Object? body});
  Future<Map<String, dynamic>> delete(String path);
}

/// The one HTTP path to the API. Attaches the bearer token, decodes the
/// envelope, and on `ACCESS_TOKEN_EXPIRED` refreshes **once** through a single
/// shared future — ten calls failing together cause one refresh — then
/// retries each. A failed refresh or a `SESSION_EXPIRED` answer hands off to
/// [onSessionExpired] and surfaces as `SESSION_EXPIRED`.
class HttpApiClient implements ApiClient {
  HttpApiClient({
    required http.Client http,
    required this.baseUrl,
    required this.readAccessToken,
    required this.refreshTokens,
    required this.onSessionExpired,
  }) : _http = http;

  final http.Client _http;
  final String baseUrl;
  Future<String?> Function() readAccessToken;
  final Future<bool> Function() refreshTokens;
  final Future<void> Function() onSessionExpired;

  /// Test hook: called after a successful refresh so a fake can rotate its token.
  void Function()? afterRefresh;

  Future<bool>? _inflightRefresh;

  @override
  Future<Map<String, dynamic>> get(String path) => _send('GET', path);

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) => _send('POST', path, body: body, extraHeaders: headers);

  @override
  Future<Map<String, dynamic>> patch(String path, {Object? body}) =>
      _send('PATCH', path, body: body);

  @override
  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? extraHeaders,
    bool retried = false,
  }) async {
    final token = await readAccessToken();
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['accept'] = 'application/json'
      ..headers.addAll(extraHeaders ?? const {});
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(const Duration(seconds: 20)),
      );
    } on http.ClientException {
      throw const ApiNetworkException();
    } on SocketException {
      throw const ApiNetworkException();
    } on TimeoutException {
      throw const ApiNetworkException();
    }

    final decoded = _decode(response);
    if (decoded is Map<String, dynamic> && decoded.containsKey('data')) {
      final data = decoded['data'];
      if (data is Map<String, dynamic>) return data;
      if (data is List) return {'_list': data};
      return {'value': data};
    }

    final error = _errorFrom(decoded, response.statusCode);
    if (error.code == 'ACCESS_TOKEN_EXPIRED' && !retried) {
      final refreshed = await _refreshOnce();
      if (refreshed) {
        return _send(method, path, body: body, extraHeaders: extraHeaders, retried: true);
      }
      await onSessionExpired();
      throw ApiException(status: 401, code: 'SESSION_EXPIRED', message: error.message);
    }
    if (error.code == 'SESSION_EXPIRED') await onSessionExpired();
    throw error;
  }

  Future<bool> _refreshOnce() {
    final inflight = _inflightRefresh;
    if (inflight != null) return inflight;
    final started = refreshTokens().then((ok) {
      if (ok) afterRefresh?.call();
      return ok;
    }).whenComplete(() => _inflightRefresh = null);
    _inflightRefresh = started;
    return started;
  }

  Object? _decode(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return null;
    }
  }

  ApiException _errorFrom(Object? decoded, int status) {
    if (decoded is Map<String, dynamic> && decoded['error'] is Map<String, dynamic>) {
      final e = decoded['error'] as Map<String, dynamic>;
      return ApiException(
        status: status,
        code: e['code'] as String? ?? 'UNKNOWN',
        message: e['message'] as String? ?? 'Something went wrong',
        details: e['details'],
      );
    }
    return ApiException(status: status, code: 'UNKNOWN', message: 'Something went wrong');
  }
}
```

(The test mutates `readAccessToken`; it is a non-final field for that reason, documented as a test hook alongside `afterRefresh`.)

- [ ] **Step 6: Test seams**

`frontend/test/helpers/fake_api.dart`:

```dart
import 'dart:async';

import 'package:raajjepro/core/api/api_client.dart';

typedef FakeHandler = FutureOr<Map<String, dynamic>> Function(Object? body);

/// Scripted API. Register a handler per `METHOD path`; a handler may throw an
/// [ApiException] or [ApiNetworkException]. Every call is recorded.
class FakeApiClient implements ApiClient {
  final Map<String, FakeHandler> handlers = {};
  final List<({String method, String path, Object? body})> calls = [];

  /// Resolves only when [release] is called — for asserting a loading state.
  Completer<void>? gate;

  void on(String method, String path, FakeHandler handler) => handlers['$method $path'] = handler;

  void fail(String method, String path, {required int status, required String code, Object? details, String message = 'failed'}) =>
      on(method, path, (_) => throw ApiException(status: status, code: code, message: message, details: details));

  void offline(String method, String path) => on(method, path, (_) => throw const ApiNetworkException());

  Future<Map<String, dynamic>> _call(String method, String path, Object? body) async {
    calls.add((method: method, path: path, body: body));
    if (gate != null) await gate!.future;
    final handler = handlers['$method $path'];
    if (handler == null) throw StateError('unscripted call: $method $path');
    return handler(body);
  }

  @override
  Future<Map<String, dynamic>> get(String path) => _call('GET', path, null);
  @override
  Future<Map<String, dynamic>> post(String path, {Object? body, Map<String, String>? headers}) => _call('POST', path, body);
  @override
  Future<Map<String, dynamic>> patch(String path, {Object? body}) => _call('PATCH', path, body);
  @override
  Future<Map<String, dynamic>> delete(String path) => _call('DELETE', path, null);
}
```

`frontend/test/helpers/pump.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/theme/app_theme.dart';

/// Pumps [screen] inside the app theme and a ProviderScope with [overrides].
/// Two frames, never pumpAndSettle — skeletons and loading buttons animate
/// forever by design (frontend/CLAUDE.md).
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  List<Override> overrides = const [],
  Map<String, WidgetBuilder> routes = const {},
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: AppTheme.light(), home: screen, routes: routes),
    ),
  );
  await settle(tester);
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
```

- [ ] **Step 7: Run** — `flutter test test/core/api/api_client_test.dart && flutter analyze --no-pub` — Expected: PASS, no issues.

- [ ] **Step 8: Commit**

```bash
git add frontend/pubspec.yaml frontend/pubspec.lock frontend/lib/core/api frontend/test/helpers frontend/test/core/api
git commit -m "Flutter API client: envelope decoding, typed errors, single-flight refresh and retry; test seams"
```

---

### Task 2: Auth core — token store, models, `AuthApi`, `AuthController`, draft store, device name

**Files:**
- Create: `frontend/lib/core/auth/token_store.dart`, `auth_models.dart`, `auth_api.dart`, `auth_controller.dart`, `form_draft_store.dart`, `device_name.dart`
- Test: `frontend/test/core/auth/auth_controller_test.dart`, `frontend/test/core/auth/auth_models_test.dart`

**Interfaces:**
- Consumes: Task 1's `ApiClient`, `ApiException`, `HttpApiClient`, `ApiConfig`.
- Produces:
  - `abstract class TokenStore { Future<TokenPair?> read(); Future<void> write(TokenPair); Future<void> clear(); }`; `SecureTokenStore` (flutter_secure_storage, keys `rp.access`, `rp.refresh`, `rp.access_exp`, `rp.refresh_exp`); `InMemoryTokenStore`.
  - `class TokenPair { accessToken, accessTokenExpiresAt, refreshToken, refreshTokenExpiresAt; fromJson }`, `class UserAccount { id, fullName, email, emailVerified, phone: PhoneNumber?, status: AccountStatus, deletionDeadlineAt, isProvider; fromJson; copyWith }`, `class PhoneNumber { dialCode, number; String get display => '$dialCode $number' }`, `enum AccountStatus { active, frozen, anonymised }`, `class VerificationOutcome { status: 'sent'|'suppressed'|'failed'; expiresAt; resendAvailableAt; fromJson }`, `class SessionInfo { id, deviceName, createdAt, lastSeenAt, current; fromJson }`.
  - `sealed class AuthState` with `AuthUnknown`, `AuthGuest`, `AuthSignedIn(UserAccount user)`, `AuthSessionExpired`.
  - `class AuthApi` (takes `ApiClient`): `register(RegisterRequest) → RegisterResult(user, tokens, verification)`, `login(email, password, deviceName) → (user, tokens)`, `refresh(refreshToken) → TokenPair`, `logout()`, `me() → UserAccount`, `sessions() → List<SessionInfo>`, `revokeSession(id)`, `sendVerification() → VerificationOutcome`, `confirmVerification(code)`, `social(provider, idToken, deviceName)`, `changePassword(current, next)`, `requestEmailChange(newEmail, currentPassword) → VerificationOutcome`, `confirmEmailChange(code) → UserAccount`, `changePhone(dialCode, number) → UserAccount`, `dataExport() → Map<String, dynamic>`, `requestDeletion() → DeletionResult(deletionRequestedAt, deletionDeadlineAt)`.
  - `class RegisterRequest { role: 'customer'|'provider', fullName, email, dialCode, number, password, businessName?, deviceName; toJson }`.
  - Providers: `tokenStoreProvider`, `httpClientProvider`, `apiClientProvider`, `authApiProvider`, `authControllerProvider` (`NotifierProvider<AuthController, AuthState>`), `deviceNameProvider` (`FutureProvider<String>`), `formDraftStoreProvider`.
  - `AuthController`: `restore()`, `signIn(email, password)`, `register(RegisterRequest) → VerificationOutcome`, `signOut()`, `refreshUser()`, `markVerified()`, `applyUser(UserAccount)`, `continueAsGuest()`, `sessionExpired()`, `Future<bool> tryRefresh()`.
  - `FormDraftStore`: `save(String formKey, Map<String, String> fields)`, `take(String formKey) → Map<String, String>?`.

- [ ] **Step 1: Models test**

`frontend/test/core/auth/auth_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_models.dart';

void main() {
  test('UserAccount parses the /v1/auth/me DTO and a null phone', () {
    final u = UserAccount.fromJson({
      'id': 'u1', 'fullName': 'Aishath', 'email': 'a@example.mv', 'emailVerified': false,
      'phone': {'dialCode': '+960', 'number': '7771234'}, 'status': 'frozen',
      'deletionDeadlineAt': '2026-10-06T10:00:00.000Z', 'isProvider': true, 'createdAt': '2026-09-06T10:00:00.000Z',
    });
    expect(u.phone?.display, '+960 7771234');
    expect(u.status, AccountStatus.frozen);
    expect(u.deletionDeadlineAt, DateTime.utc(2026, 10, 6, 10));
    expect(u.isProvider, isTrue);
    final noPhone = UserAccount.fromJson({...u.toJson(), 'phone': null, 'status': 'active', 'deletionDeadlineAt': null});
    expect(noPhone.phone, isNull);
    expect(noPhone.status, AccountStatus.active);
  });

  test('an unknown status parses as active rather than crashing (additive-only API)', () {
    final u = UserAccount.fromJson({'id': 'u', 'fullName': 'x', 'email': 'e', 'emailVerified': true, 'phone': null, 'status': 'something_new', 'deletionDeadlineAt': null, 'isProvider': false, 'createdAt': '2026-09-06T10:00:00.000Z'});
    expect(u.status, AccountStatus.active);
  });

  test('TokenPair and VerificationOutcome parse timestamps', () {
    final t = TokenPair.fromJson({'accessToken': 'a', 'accessTokenExpiresAt': '2026-09-06T10:15:00.000Z', 'refreshToken': 'r', 'refreshTokenExpiresAt': '2026-10-06T10:00:00.000Z'});
    expect(t.accessTokenExpiresAt.minute, 15);
    final v = VerificationOutcome.fromJson({'status': 'suppressed', 'expiresAt': '2026-09-06T10:10:00.000Z', 'resendAvailableAt': '2026-09-06T10:01:00.000Z'});
    expect(v.status, VerificationStatus.suppressed);
  });
}
```

- [ ] **Step 2: Controller test**

`frontend/test/core/auth/auth_controller_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_api.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/token_store.dart';

import '../../helpers/fake_api.dart';

Map<String, dynamic> userJson({bool verified = false, String status = 'active'}) => {
  'id': 'u1', 'fullName': 'Aishath Naeema', 'email': 'aishath@example.mv', 'emailVerified': verified, 'phone': {'dialCode': '+960', 'number': '7771234'},
  'status': status, 'deletionDeadlineAt': null, 'isProvider': false, 'createdAt': '2026-09-06T10:00:00.000Z',
};
Map<String, dynamic> tokensJson([String suffix = '']) => {
  'accessToken': 'access$suffix', 'accessTokenExpiresAt': '2026-09-06T10:15:00.000Z', 'refreshToken': 'refresh$suffix', 'refreshTokenExpiresAt': '2026-10-06T10:00:00.000Z',
};

void main() {
  late FakeApiClient api;
  late InMemoryTokenStore store;
  late ProviderContainer container;

  setUp(() {
    api = FakeApiClient();
    store = InMemoryTokenStore();
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
      tokenStoreProvider.overrideWithValue(store),
      deviceNameProvider.overrideWith((_) async => 'Test phone'),
    ]);
    addTearDown(container.dispose);
  });

  test('starts unknown; restore() with no tokens → guest', () async {
    expect(container.read(authControllerProvider), isA<AuthUnknown>());
    await container.read(authControllerProvider.notifier).restore();
    expect(container.read(authControllerProvider), isA<AuthGuest>());
  });

  test('restore() with tokens loads me and is signed in; a SESSION_EXPIRED answer → sessionExpired and tokens cleared', () async {
    await store.write(TokenPair.fromJson(tokensJson()));
    api.on('GET', '/v1/auth/me', (_) => userJson(verified: true));
    await container.read(authControllerProvider.notifier).restore();
    final state = container.read(authControllerProvider);
    expect(state, isA<AuthSignedIn>());
    expect((state as AuthSignedIn).user.emailVerified, isTrue);

    api.fail('GET', '/v1/auth/me', status: 401, code: 'SESSION_EXPIRED');
    await container.read(authControllerProvider.notifier).refreshUser();
    expect(container.read(authControllerProvider), isA<AuthSessionExpired>());
    expect(await store.read(), isNull);
  });

  test('signIn stores tokens with the device name and becomes signed in; a wrong password rethrows and stays guest', () async {
    api.on('POST', '/v1/auth/login', (body) {
      expect((body as Map)['deviceName'], 'Test phone');
      return {'user': userJson(), 'tokens': tokensJson()};
    });
    await container.read(authControllerProvider.notifier).signIn('aishath@example.mv', 'pw');
    expect(container.read(authControllerProvider), isA<AuthSignedIn>());
    expect((await store.read())?.refreshToken, 'refresh');

    await container.read(authControllerProvider.notifier).signOut();
    api.fail('POST', '/v1/auth/login', status: 401, code: 'INVALID_CREDENTIALS');
    await expectLater(container.read(authControllerProvider.notifier).signIn('a', 'b'), throwsA(isA<ApiException>()));
    expect(container.read(authControllerProvider), isA<AuthGuest>());
  });

  test('register signs in unverified and returns the verification outcome', () async {
    api.on('POST', '/v1/auth/register', (_) => {'user': userJson(), 'tokens': tokensJson(), 'verification': {'status': 'sent', 'expiresAt': '2026-09-06T10:10:00.000Z', 'resendAvailableAt': '2026-09-06T10:01:00.000Z'}});
    final outcome = await container.read(authControllerProvider.notifier).register(RegisterRequest(role: AccountRole.customer, fullName: 'A', email: 'a@example.mv', dialCode: '+960', number: '7771234', password: 'password1', deviceName: 'Test phone'));
    expect(outcome.status, VerificationStatus.sent);
    final signedIn = container.read(authControllerProvider) as AuthSignedIn;
    expect(signedIn.user.emailVerified, isFalse);
    final call = api.calls.single;
    expect((call.body as Map)['acceptTerms'], isTrue);
    expect((call.body as Map).containsKey('businessName'), isFalse);
  });

  test('tryRefresh rotates the stored pair; a failed refresh clears tokens and reports false', () async {
    await store.write(TokenPair.fromJson(tokensJson()));
    api.on('POST', '/v1/auth/refresh', (body) {
      expect((body as Map)['refreshToken'], 'refresh');
      return {'tokens': tokensJson('2')};
    });
    expect(await container.read(authControllerProvider.notifier).tryRefresh(), isTrue);
    expect((await store.read())?.accessToken, 'access2');
    api.fail('POST', '/v1/auth/refresh', status: 401, code: 'SESSION_EXPIRED');
    expect(await container.read(authControllerProvider.notifier).tryRefresh(), isFalse);
    expect(await store.read(), isNull);
  });

  test('signOut calls logout best-effort and always ends as guest, even offline', () async {
    await store.write(TokenPair.fromJson(tokensJson()));
    api.on('GET', '/v1/auth/me', (_) => userJson());
    await container.read(authControllerProvider.notifier).restore();
    api.offline('POST', '/v1/auth/logout');
    await container.read(authControllerProvider.notifier).signOut();
    expect(container.read(authControllerProvider), isA<AuthGuest>());
    expect(await store.read(), isNull);
  });

  test('markVerified flips the flag without a network call; applyUser replaces the user', () async {
    await store.write(TokenPair.fromJson(tokensJson()));
    api.on('GET', '/v1/auth/me', (_) => userJson());
    final c = container.read(authControllerProvider.notifier);
    await c.restore();
    c.markVerified();
    expect((container.read(authControllerProvider) as AuthSignedIn).user.emailVerified, isTrue);
    c.applyUser(UserAccount.fromJson(userJson(status: 'frozen')));
    expect((container.read(authControllerProvider) as AuthSignedIn).user.status, AccountStatus.frozen);
  });
}
```

- [ ] **Step 3: Run to fail** — `flutter test test/core/auth` — Expected: FAIL.

- [ ] **Step 4: `auth_models.dart`**

```dart
enum AccountStatus { active, frozen, anonymised }

enum AccountRole { customer, provider }

enum VerificationStatus { sent, suppressed, failed }

DateTime? _date(Object? v) => v is String ? DateTime.parse(v).toUtc() : null;

class PhoneNumber {
  const PhoneNumber({required this.dialCode, required this.number});
  final String dialCode;
  final String number;

  /// User-supplied text, shown as typed. Never with a check mark (plan §Phase 3).
  String get display => '$dialCode $number';

  factory PhoneNumber.fromJson(Map<String, dynamic> j) =>
      PhoneNumber(dialCode: j['dialCode'] as String, number: j['number'] as String);
}

class UserAccount {
  const UserAccount({
    required this.id, required this.fullName, required this.email, required this.emailVerified,
    required this.phone, required this.status, required this.deletionDeadlineAt, required this.isProvider, required this.createdAt,
  });

  final String id;
  final String fullName;
  final String email;
  final bool emailVerified;
  final PhoneNumber? phone;
  final AccountStatus status;
  final DateTime? deletionDeadlineAt;
  final bool isProvider;
  final DateTime createdAt;

  /// An unrecognised status reads as `active`: the API is additive-only and a
  /// new enum value must not crash an installed app (docs/api/versioning.md).
  factory UserAccount.fromJson(Map<String, dynamic> j) => UserAccount(
    id: j['id'] as String,
    fullName: j['fullName'] as String,
    email: j['email'] as String,
    emailVerified: j['emailVerified'] as bool,
    phone: j['phone'] is Map<String, dynamic> ? PhoneNumber.fromJson(j['phone'] as Map<String, dynamic>) : null,
    status: AccountStatus.values.asNameMap()[j['status'] as String?] ?? AccountStatus.active,
    deletionDeadlineAt: _date(j['deletionDeadlineAt']),
    isProvider: j['isProvider'] as bool? ?? false,
    createdAt: _date(j['createdAt']) ?? DateTime.now().toUtc(),
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'fullName': fullName, 'email': email, 'emailVerified': emailVerified,
    'phone': phone == null ? null : {'dialCode': phone!.dialCode, 'number': phone!.number},
    'status': status.name, 'deletionDeadlineAt': deletionDeadlineAt?.toIso8601String(), 'isProvider': isProvider, 'createdAt': createdAt.toIso8601String(),
  };

  UserAccount copyWith({bool? emailVerified, String? email, PhoneNumber? phone, AccountStatus? status, DateTime? deletionDeadlineAt}) => UserAccount(
    id: id, fullName: fullName, email: email ?? this.email, emailVerified: emailVerified ?? this.emailVerified,
    phone: phone ?? this.phone, status: status ?? this.status, deletionDeadlineAt: deletionDeadlineAt ?? this.deletionDeadlineAt,
    isProvider: isProvider, createdAt: createdAt,
  );
}

class TokenPair {
  const TokenPair({required this.accessToken, required this.accessTokenExpiresAt, required this.refreshToken, required this.refreshTokenExpiresAt});
  final String accessToken;
  final DateTime accessTokenExpiresAt;
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;

  factory TokenPair.fromJson(Map<String, dynamic> j) => TokenPair(
    accessToken: j['accessToken'] as String,
    accessTokenExpiresAt: _date(j['accessTokenExpiresAt'])!,
    refreshToken: j['refreshToken'] as String,
    refreshTokenExpiresAt: _date(j['refreshTokenExpiresAt'])!,
  );
}

class VerificationOutcome {
  const VerificationOutcome({required this.status, required this.expiresAt, required this.resendAvailableAt});
  final VerificationStatus status;
  final DateTime expiresAt;
  final DateTime resendAvailableAt;

  factory VerificationOutcome.fromJson(Map<String, dynamic> j) => VerificationOutcome(
    status: VerificationStatus.values.asNameMap()[j['status'] as String?] ?? VerificationStatus.failed,
    expiresAt: _date(j['expiresAt'])!,
    resendAvailableAt: _date(j['resendAvailableAt'])!,
  );
}

class SessionInfo {
  const SessionInfo({required this.id, required this.deviceName, required this.createdAt, required this.lastSeenAt, required this.current});
  final String id;
  final String deviceName;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final bool current;

  factory SessionInfo.fromJson(Map<String, dynamic> j) => SessionInfo(
    id: j['id'] as String, deviceName: j['deviceName'] as String,
    createdAt: _date(j['createdAt'])!, lastSeenAt: _date(j['lastSeenAt'])!, current: j['current'] as bool,
  );
}

class DeletionResult {
  const DeletionResult({required this.deletionRequestedAt, required this.deletionDeadlineAt});
  final DateTime deletionRequestedAt;
  final DateTime deletionDeadlineAt;
  factory DeletionResult.fromJson(Map<String, dynamic> j) =>
      DeletionResult(deletionRequestedAt: _date(j['deletionRequestedAt'])!, deletionDeadlineAt: _date(j['deletionDeadlineAt'])!);
}

class RegisterRequest {
  const RegisterRequest({required this.role, required this.fullName, required this.email, required this.dialCode, required this.number, required this.password, this.businessName, required this.deviceName});
  final AccountRole role;
  final String fullName;
  final String email;
  final String dialCode;
  final String number;
  final String password;
  final String? businessName;
  final String deviceName;

  Map<String, dynamic> toJson() => {
    'role': role.name, 'fullName': fullName, 'email': email,
    'phone': {'dialCode': dialCode, 'number': number}, 'password': password,
    if (role == AccountRole.provider && businessName != null) 'businessName': businessName,
    'acceptTerms': true, 'deviceName': deviceName,
  };
}

sealed class AuthState {
  const AuthState();
}

class AuthUnknown extends AuthState { const AuthUnknown(); }
class AuthGuest extends AuthState { const AuthGuest(); }
class AuthSessionExpired extends AuthState { const AuthSessionExpired(); }
class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.user);
  final UserAccount user;
}
```

- [ ] **Step 5: `token_store.dart`**

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:raajjepro/core/auth/auth_models.dart';

abstract class TokenStore {
  Future<TokenPair?> read();
  Future<void> write(TokenPair tokens);
  Future<void> clear();
}

/// Tokens live in the platform keystore, never in shared preferences.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  static const _access = 'rp.access', _accessExp = 'rp.access_exp', _refresh = 'rp.refresh', _refreshExp = 'rp.refresh_exp';

  @override
  Future<TokenPair?> read() async {
    final values = await Future.wait([_s.read(key: _access), _s.read(key: _accessExp), _s.read(key: _refresh), _s.read(key: _refreshExp)]);
    if (values.any((v) => v == null)) return null;
    return TokenPair(
      accessToken: values[0]!, accessTokenExpiresAt: DateTime.parse(values[1]!),
      refreshToken: values[2]!, refreshTokenExpiresAt: DateTime.parse(values[3]!),
    );
  }

  @override
  Future<void> write(TokenPair t) => Future.wait([
    _s.write(key: _access, value: t.accessToken), _s.write(key: _accessExp, value: t.accessTokenExpiresAt.toIso8601String()),
    _s.write(key: _refresh, value: t.refreshToken), _s.write(key: _refreshExp, value: t.refreshTokenExpiresAt.toIso8601String()),
  ]);

  @override
  Future<void> clear() => Future.wait([_s.delete(key: _access), _s.delete(key: _accessExp), _s.delete(key: _refresh), _s.delete(key: _refreshExp)]);
}

class InMemoryTokenStore implements TokenStore {
  TokenPair? _tokens;
  @override
  Future<TokenPair?> read() async => _tokens;
  @override
  Future<void> write(TokenPair tokens) async => _tokens = tokens;
  @override
  Future<void> clear() async => _tokens = null;
}
```

- [ ] **Step 6: `auth_api.dart`**

```dart
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_models.dart';

/// Typed calls to /v1/auth and /v1/users/me. Bodies and paths are the backend
/// plan's route blocks, verbatim. No rule lives here — the server decides.
class AuthApi {
  const AuthApi(this._api);
  final ApiClient _api;

  Future<({UserAccount user, TokenPair tokens, VerificationOutcome verification})> register(RegisterRequest request, {required String idempotencyKey}) async {
    final d = await _api.post('/v1/auth/register', body: request.toJson(), headers: {'idempotency-key': idempotencyKey});
    return (user: UserAccount.fromJson(d['user'] as Map<String, dynamic>), tokens: TokenPair.fromJson(d['tokens'] as Map<String, dynamic>), verification: VerificationOutcome.fromJson(d['verification'] as Map<String, dynamic>));
  }

  Future<({UserAccount user, TokenPair tokens})> login(String email, String password, String deviceName) async {
    final d = await _api.post('/v1/auth/login', body: {'email': email, 'password': password, 'deviceName': deviceName});
    return (user: UserAccount.fromJson(d['user'] as Map<String, dynamic>), tokens: TokenPair.fromJson(d['tokens'] as Map<String, dynamic>));
  }

  Future<TokenPair> refresh(String refreshToken) async =>
      TokenPair.fromJson((await _api.post('/v1/auth/refresh', body: {'refreshToken': refreshToken}))['tokens'] as Map<String, dynamic>);

  Future<void> logout() => _api.post('/v1/auth/logout');
  Future<UserAccount> me() async => UserAccount.fromJson(await _api.get('/v1/auth/me'));

  Future<List<SessionInfo>> sessions() async =>
      ((await _api.get('/v1/auth/sessions'))['_list'] as List).cast<Map<String, dynamic>>().map(SessionInfo.fromJson).toList();
  Future<void> revokeSession(String id) => _api.delete('/v1/auth/sessions/$id');

  Future<VerificationOutcome> sendVerification() async => VerificationOutcome.fromJson(await _api.post('/v1/auth/verify-email/send'));
  Future<void> confirmVerification(String code) => _api.post('/v1/auth/verify-email/confirm', body: {'code': code});
  Future<void> social(String provider, String idToken, String deviceName) => _api.post('/v1/auth/social/$provider', body: {'idToken': idToken, 'deviceName': deviceName});

  Future<void> changePassword(String currentPassword, String newPassword) =>
      _api.post('/v1/users/me/change-password', body: {'currentPassword': currentPassword, 'newPassword': newPassword});
  Future<VerificationOutcome> requestEmailChange(String newEmail, String currentPassword) async =>
      VerificationOutcome.fromJson(await _api.post('/v1/users/me/change-email/request', body: {'newEmail': newEmail, 'currentPassword': currentPassword}));
  Future<UserAccount> confirmEmailChange(String code) async => UserAccount.fromJson(await _api.post('/v1/users/me/change-email/confirm', body: {'code': code}));
  Future<UserAccount> changePhone(String dialCode, String number) async =>
      UserAccount.fromJson(await _api.patch('/v1/users/me/phone', body: {'dialCode': dialCode, 'number': number}));
  Future<Map<String, dynamic>> dataExport() => _api.get('/v1/users/me/data-export');
  Future<DeletionResult> requestDeletion() async => DeletionResult.fromJson(await _api.post('/v1/users/me/deletion-request'));
}
```

- [ ] **Step 7: `device_name.dart`, `form_draft_store.dart`**

```dart
// device_name.dart
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "iPhone 14", "Pixel 7" — what the sessions list shows. Falls back to the
/// platform name; never fails a sign-in over it.
final deviceNameProvider = FutureProvider<String>((ref) async {
  try {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      return '${a.manufacturer} ${a.model}'.trim();
    }
    if (Platform.isIOS) {
      final i = await info.iosInfo;
      return i.name;
    }
  } on Object {
    // fall through
  }
  return Platform.operatingSystem;
});
```

```dart
// form_draft_store.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keeps what a user was typing across a session-expired → sign-in → return
/// path. That is the one promise the Session Expired screen makes, and it
/// must be true. In memory only; a process restart legitimately loses it,
/// and the screen's copy never claims more than "after you sign in".
class FormDraftStore {
  final Map<String, Map<String, String>> _drafts = {};
  void save(String formKey, Map<String, String> fields) => _drafts[formKey] = Map.of(fields);
  Map<String, String>? take(String formKey) => _drafts.remove(formKey);
  Map<String, String>? peek(String formKey) => _drafts[formKey];
}

final formDraftStoreProvider = Provider<FormDraftStore>((_) => FormDraftStore());
```

- [ ] **Step 8: `auth_controller.dart`**

```dart
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/api/api_config.dart';
import 'package:raajjepro/core/auth/auth_api.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/device_name.dart';
import 'package:raajjepro/core/auth/token_store.dart';

final tokenStoreProvider = Provider<TokenStore>((_) => SecureTokenStore());
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final store = ref.watch(tokenStoreProvider);
  return HttpApiClient(
    http: ref.watch(httpClientProvider),
    baseUrl: ApiConfig.baseUrl,
    readAccessToken: () async => (await store.read())?.accessToken,
    refreshTokens: () => ref.read(authControllerProvider.notifier).tryRefresh(),
    onSessionExpired: () async => ref.read(authControllerProvider.notifier).sessionExpired(),
  );
});

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(apiClientProvider)));

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

/// The one auth state the root widget switches on (spec §8). Tokens live in
/// [TokenStore]; the user comes from `/v1/auth/me` and is refreshed in the
/// background on restore so a verification or freeze done elsewhere shows.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthUnknown();

  AuthApi get _api => ref.read(authApiProvider);
  TokenStore get _store => ref.read(tokenStoreProvider);

  Future<String> _deviceName() async {
    try {
      return await ref.read(deviceNameProvider.future);
    } on Object {
      return 'Unknown device';
    }
  }

  Future<void> restore() async {
    final tokens = await _store.read();
    if (tokens == null) {
      state = const AuthGuest();
      return;
    }
    await refreshUser();
  }

  /// Re-reads `me`. A dead session becomes [AuthSessionExpired]; a network
  /// failure keeps whatever state we had — offline is not signed out.
  Future<void> refreshUser() async {
    try {
      state = AuthSignedIn(await _api.me());
    } on ApiException catch (e) {
      if (e.code == 'SESSION_EXPIRED' || e.code == 'UNAUTHENTICATED') await sessionExpired();
    } on ApiNetworkException {
      if (state is AuthUnknown) state = const AuthGuest();
    }
  }

  Future<void> signIn(String email, String password) async {
    final result = await _api.login(email, password, await _deviceName());
    await _store.write(result.tokens);
    state = AuthSignedIn(result.user);
  }

  Future<VerificationOutcome> register(RegisterRequest request) async {
    final result = await _api.register(request, idempotencyKey: _idempotencyKey());
    await _store.write(result.tokens);
    state = AuthSignedIn(result.user);
    return result.verification;
  }

  Future<bool> tryRefresh() async {
    final tokens = await _store.read();
    if (tokens == null) return false;
    try {
      await _store.write(await _api.refresh(tokens.refreshToken));
      return true;
    } on ApiException {
      await _store.clear();
      return false;
    } on ApiNetworkException {
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _api.logout();
    } on Object {
      // Best effort: the local sign-out must not depend on the network.
    }
    await _store.clear();
    state = const AuthGuest();
  }

  Future<void> sessionExpired() async {
    await _store.clear();
    state = const AuthSessionExpired();
  }

  void continueAsGuest() => state = const AuthGuest();

  void markVerified() {
    final s = state;
    if (s is AuthSignedIn) state = AuthSignedIn(s.user.copyWith(emailVerified: true));
  }

  void applyUser(UserAccount user) => state = AuthSignedIn(user);

  /// A UUID v4 — the client key registration's idempotency requires.
  String _idempotencyKey() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}
```

- [ ] **Step 9: Run** — `flutter test test/core/auth && flutter analyze --no-pub` — Expected: PASS, clean. (If `deviceNameProvider.overrideWith((_) async => …)` needs a different override shape under Riverpod 3, use `deviceNameProvider.overrideWith((ref) => Future.value('Test phone'))`.)

- [ ] **Step 10: Commit**

```bash
git add frontend/lib/core/auth frontend/test/core/auth
git commit -m "Auth core: secure token store, typed auth API, AuthController state machine, form draft store"
```

---

### Task 3: `CrashReporter` over Sentry, and `main.dart`

**Files:**
- Create: `frontend/lib/core/crash/crash_reporter.dart`
- Modify: `frontend/lib/main.dart`
- Test: `frontend/test/core/crash/crash_reporter_test.dart`, update `frontend/test/app_boot_test.dart`

**Interfaces:**
- Produces: `abstract class CrashReporter { Future<void> init(); Future<void> recordError(Object error, StackTrace? stack, {bool fatal}); Future<void> setUserId(String? id); }`, `NoopCrashReporter`, `SentryCrashReporter(dsn)`, `CrashReporter crashReporterFor(String dsn)` (empty → noop), `crashReporterProvider`, `CrashConfig.dsn` from `String.fromEnvironment('SENTRY_DSN')`.

- [ ] **Step 1: Test**

`frontend/test/core/crash/crash_reporter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/crash/crash_reporter.dart';

void main() {
  test('an empty DSN yields the no-op reporter; a DSN yields Sentry', () {
    expect(crashReporterFor(''), isA<NoopCrashReporter>());
    expect(crashReporterFor('https://key@o1.ingest.sentry.io/1'), isA<SentryCrashReporter>());
  });

  test('the no-op reporter accepts every call and never throws', () async {
    final r = NoopCrashReporter();
    await r.init();
    await r.recordError(StateError('x'), StackTrace.current);
    await r.setUserId('u1');
    await r.setUserId(null);
  });

  test('the Sentry reporter attaches only the user id, never email or phone', () {
    // SentryCrashReporter.userFor is the one place a user is described to the vendor.
    final user = SentryCrashReporter.userFor('u1');
    expect(user.id, 'u1');
    expect(user.email, isNull);
    expect(user.username, isNull);
    expect(user.data, isNull);
  });
}
```

- [ ] **Step 2: Run to fail** — Expected: FAIL.

- [ ] **Step 3: `crash_reporter.dart`**

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

abstract final class CrashConfig {
  /// Empty by default: no account is needed to build (plan §4 pulls crash
  /// reporting forward to Phase 3; the vendor DSN arrives at deployment —
  /// docs/deferred-verification.md L9).
  static const dsn = String.fromEnvironment('SENTRY_DSN');
}

/// The seam over the crash vendor (spec §8). Domain code never imports Sentry.
abstract class CrashReporter {
  Future<void> init();
  Future<void> recordError(Object error, StackTrace? stack, {bool fatal = false});
  /// The user id only — never an email or phone (root CLAUDE.md 1d: no PII in event logs).
  Future<void> setUserId(String? id);
}

class NoopCrashReporter implements CrashReporter {
  @override
  Future<void> init() async {}
  @override
  Future<void> recordError(Object error, StackTrace? stack, {bool fatal = false}) async {
    if (kDebugMode) debugPrint('crash (unreported, no DSN): $error');
  }
  @override
  Future<void> setUserId(String? id) async {}
}

class SentryCrashReporter implements CrashReporter {
  SentryCrashReporter(this.dsn);
  final String dsn;

  static SentryUser userFor(String id) => SentryUser(id: id);

  @override
  Future<void> init() => SentryFlutter.init((options) {
    options.dsn = dsn;
    options.sendDefaultPii = false;
    options.tracesSampleRate = 0;
  });

  @override
  Future<void> recordError(Object error, StackTrace? stack, {bool fatal = false}) async {
    await Sentry.captureException(error, stackTrace: stack);
  }

  @override
  Future<void> setUserId(String? id) => Sentry.configureScope((scope) => scope.setUser(id == null ? null : userFor(id)));
}

CrashReporter crashReporterFor(String dsn) => dsn.isEmpty ? NoopCrashReporter() : SentryCrashReporter(dsn);

final crashReporterProvider = Provider<CrashReporter>((_) => crashReporterFor(CrashConfig.dsn));
```

- [ ] **Step 4: `main.dart`**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/app.dart';
import 'package:raajjepro/core/crash/crash_reporter.dart';

Future<void> main() async {
  final reporter = crashReporterFor(CrashConfig.dsn);
  await reporter.init();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(reporter.recordError(details.exception, details.stack, fatal: true));
  };
  runZonedGuarded(
    () => runApp(
      ProviderScope(
        overrides: [crashReporterProvider.overrideWithValue(reporter)],
        child: const RaajjeProApp(),
      ),
    ),
    (error, stack) => unawaited(reporter.recordError(error, stack, fatal: true)),
  );
}
```

`AuthController.applyUser`/`signIn`/`restore` set the user id on the reporter: in `auth_controller.dart`, wherever `state = AuthSignedIn(...)` is assigned, follow with `unawaited(ref.read(crashReporterProvider).setUserId(user.id))`, and `setUserId(null)` in `signOut` and `sessionExpired`. (Import `dart:async` for `unawaited`.)

- [ ] **Step 5: Update `app_boot_test.dart`** to wrap `RaajjeProApp` in `ProviderScope` with `tokenStoreProvider.overrideWithValue(InMemoryTokenStore())` and `crashReporterProvider.overrideWithValue(NoopCrashReporter())` — the root will switch on auth state from Task 7; until then the placeholder boots as before.

- [ ] **Step 6: Run** — `flutter test && flutter analyze --no-pub` — Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/core/crash frontend/lib/main.dart frontend/test
git commit -m "Crash reporting behind a CrashReporter seam: Sentry with the DSN optional, user id only"
```

---

### Task 4: Sign In screen

**Files:**
- Create: `frontend/lib/features/auth/presentation/widgets/auth_hero.dart`, `frontend/lib/features/auth/presentation/widgets/social_sign_in_row.dart`, `frontend/lib/features/auth/controller/sign_in_controller.dart`, `frontend/lib/features/auth/presentation/sign_in_screen.dart`
- Test: `frontend/test/features/auth/sign_in_screen_test.dart`

**Reference:** `mockups/design-composer/Sign In.dc.html` — gradient hero (wordmark `Raajje` + `Pro` in primary, `🇲🇻 Maldives Local Service Marketplace`), `Welcome back` / `Sign in to your RaajjePro account`, failure banner `That email and password combination didn't work. Check both and try again.` (both fields keep their values, borders go error-red), `Email address`, `Password` with reveal, `Forgot password?` right-aligned, primary `Sign In` (`Signing in…` while busy), `or continue with`, four round buttons Google · Apple · Facebook · Viber (placeholder glyph letters, never hotlinked icons), `Don't have an account? Create Account`, `Continue as Guest`, and the guest line `Browsing, searching and viewing providers need no account. Sign in when you want to save, book or message.`

**Interfaces:**
- Produces: `SignInScreen` (`static const routeName = '/sign-in'`), `AuthHero({required String title, required String subtitle})`, `SocialSignInRow({required void Function(String provider) onTap})`, `signInControllerProvider` (`NotifierProvider<SignInController, SignInState>`; `SignInState { busy, failed, offline, socialNotice: String? }`; methods `submit(email, password)`, `social(provider)`, `clearFailure()`).
- Routes it navigates to (registered in Task 7): `RegisterScreen.routeName`, `'/forgot-password'` (Phase 3b placeholder), home `'/'`.

- [ ] **Step 1: Failing widget test**

`frontend/test/features/auth/sign_in_screen_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/features/auth/presentation/sign_in_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../core/auth/auth_controller_test.dart' show tokensJson, userJson;
import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

void main() {
  late FakeApiClient api;
  Future<void> pump(WidgetTester tester) => pumpScreen(
        tester,
        const SignInScreen(),
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          deviceNameProvider.overrideWith((_) async => 'Test phone'),
        ],
        routes: {'/register': (_) => const Scaffold(body: Text('REGISTER')), '/forgot-password': (_) => const Scaffold(body: Text('FORGOT')), '/': (_) => const Scaffold(body: Text('HOME'))},
      );

  setUp(() => api = FakeApiClient());

  Future<void> fill(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('signin-email')), 'aishath@example.mv');
    await tester.enterText(find.byKey(const Key('signin-password')), 'seabreeze-24');
  }

  testWidgets('default state: the prototype copy, four third-party buttons including Apple, no SMS anywhere', (tester) async {
    await pump(tester);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in to your RaajjePro account'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Continue as Guest'), findsOneWidget);
    for (final p in ['Google', 'Apple', 'Facebook', 'Viber']) {
      expect(find.bySemanticsLabel('Continue with $p'), findsOneWidget);
    }
    expect(find.textContaining('SMS'), findsNothing);
    expect(find.textContaining('text message'), findsNothing);
    expect(find.textContaining('Browsing, searching and viewing providers need no account'), findsOneWidget);
  });

  testWidgets('submitting shows the button\'s own loading state, then success signs in', (tester) async {
    api.gate = Completer<void>();
    api.on('POST', '/v1/auth/login', (_) => {'user': userJson(), 'tokens': tokensJson()});
    await pump(tester);
    await fill(tester);
    await tester.tap(find.widgetWithText(AppButton, 'Sign In'));
    await tester.pump();
    expect(find.text('Signing in…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing); // the button spins, not the page
    api.gate!.complete();
    await settle(tester);
    expect(api.calls.single.path, '/v1/auth/login');
  });

  testWidgets('a wrong password shows one undifferentiated message and keeps both values and the reveal state', (tester) async {
    api.fail('POST', '/v1/auth/login', status: 401, code: 'INVALID_CREDENTIALS');
    await pump(tester);
    await fill(tester);
    await tester.tap(find.bySemanticsLabel('Show password'));
    await tester.pump();
    await tester.tap(find.widgetWithText(AppButton, 'Sign In'));
    await settle(tester);
    expect(find.text("That email and password combination didn't work. Check both and try again."), findsOneWidget);
    expect(find.text('aishath@example.mv'), findsOneWidget);
    expect(find.text('seabreeze-24'), findsOneWidget); // revealed, so visible as text
    expect(find.bySemanticsLabel('Hide password'), findsOneWidget);
    expect(find.textContaining('email', findRichText: true).evaluate().any((e) => (e.widget as Text).data?.contains('not found') ?? false), isFalse);
  });

  testWidgets('offline shows an inline notice with retry, never a raw error', (tester) async {
    api.offline('POST', '/v1/auth/login');
    await pump(tester);
    await fill(tester);
    await tester.tap(find.widgetWithText(AppButton, 'Sign In'));
    await settle(tester);
    expect(find.text('No internet connection.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('a third-party button answers with an inline "not available yet" notice', (tester) async {
    api.fail('POST', '/v1/auth/social/apple', status: 422, code: 'SOCIAL_AUTH_UNAVAILABLE', message: "Sign-in with apple isn't available yet — use your email and password");
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('Continue with Apple'));
    await settle(tester);
    expect(find.textContaining("isn't available yet"), findsOneWidget);
  });

  testWidgets('Create Account, Forgot password and Continue as Guest navigate', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Create Account'));
    await settle(tester);
    expect(find.text('REGISTER'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.text('Forgot password?'));
    await settle(tester);
    expect(find.text('FORGOT'), findsOneWidget);
  });

  testWidgets('every control meets the 48 dp floor', (tester) async {
    await pump(tester);
    for (final p in tester.widgetList<Pressable>(find.byType(Pressable))) {
      final size = tester.getSize(find.byWidget(p));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });
}
```

- [ ] **Step 2: Run to fail** — `flutter test test/features/auth/sign_in_screen_test.dart` — Expected: FAIL.

- [ ] **Step 3: `auth_hero.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:raajjepro/core/theme/app_theme.dart';

/// The gradient header Sign In and Register share (`Sign In.dc.html`): the
/// brand gradient with three faint discs, the wordmark, and a title pair.
class AuthHero extends StatelessWidget {
  const AuthHero({required this.title, required this.subtitle, super.key});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.gradientStart, colors.primary, colors.primaryPressed],
          stops: const [0, .55, 1],
        ),
      ),
      child: Stack(
        children: [
          for (final (dx, dy, d) in [(-34.0, -46.0, 150.0), (64.0, 64.0, 90.0), (-30.0, 200.0, 110.0)])
            PositionedDirectional(
              end: dx < 0 ? dx : null,
              start: dx >= 0 ? null : null,
              top: dy,
              child: ExcludeSemantics(
                child: Container(
                  width: d,
                  height: d,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: colors.onPrimary.withValues(alpha: .08)),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.xxl, 54, AppSpacing.xxl, 26),
            child: Column(
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Raajje', style: type.screenTitle.copyWith(color: colors.onPrimary)),
                    TextSpan(text: 'Pro', style: type.screenTitle.copyWith(color: colors.accentBorder)),
                  ]),
                  semanticsLabel: 'RaajjePro',
                ),
                const SizedBox(height: AppSpacing.xs),
                Text('🇲🇻 Maldives Local Service Marketplace', style: type.caption.copyWith(color: colors.onPrimary.withValues(alpha: .85))),
                const SizedBox(height: AppSpacing.xl),
                Text(title, style: type.screenTitle.copyWith(color: colors.onPrimary), textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.xs),
                Text(subtitle, style: type.body.copyWith(color: colors.onPrimary.withValues(alpha: .85)), textAlign: TextAlign.center),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

(Keep the disc positions simple and directional; the exact offsets are decoration and may be tidied — what matters is the gradient, wordmark and titles.)

- [ ] **Step 4: `social_sign_in_row.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// The four third-party buttons (`Sign In.dc.html`). Apple is present because
/// App Review requires it wherever another sign-in is offered (plan §1
/// divergence 6). Glyphs are letters, never hotlinked brand assets. Every
/// provider is a stub in v1: the tap surfaces the API's own "not available
/// yet" notice inline (plan §6 — real social auth is post-v1).
class SocialSignInRow extends StatelessWidget {
  const SocialSignInRow({required this.onTap, super.key});
  final void Function(String provider) onTap;

  static const providers = [('google', 'Google', 'G'), ('apple', 'Apple', 'A'), ('facebook', 'Facebook', 'f'), ('viber', 'Viber', 'V')];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (id, name, glyph) in providers)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.sm),
            child: Pressable(
              semanticLabel: 'Continue with $name',
              onTap: () => onTap(id),
              child: Container(
                width: AppSizes.touchTarget,
                height: AppSizes.touchTarget,
                decoration: BoxDecoration(shape: BoxShape.circle, color: colors.surface, border: Border.all(color: colors.border, width: AppSizes.inputStroke)),
                alignment: Alignment.center,
                child: Text(glyph, style: type.cardTitle.copyWith(color: colors.ink)),
              ),
            ),
          ),
      ],
    );
  }
}
```

(Check `Pressable`'s constructor in `lib/shared/motion/pressable.dart` for the exact parameter names — `semanticLabel`/`onTap` are the Phase 1 names; adjust if it reads `label`.)

- [ ] **Step 5: `sign_in_controller.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_api.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/device_name.dart';

class SignInState {
  const SignInState({this.busy = false, this.failed = false, this.offline = false, this.socialNotice});
  final bool busy;
  /// One undifferentiated failure: never "email not found" vs "wrong password".
  final bool failed;
  final bool offline;
  final String? socialNotice;

  SignInState copyWith({bool? busy, bool? failed, bool? offline, String? socialNotice, bool clearNotice = false}) => SignInState(
    busy: busy ?? this.busy, failed: failed ?? this.failed, offline: offline ?? this.offline,
    socialNotice: clearNotice ? null : (socialNotice ?? this.socialNotice),
  );
}

final signInControllerProvider = NotifierProvider<SignInController, SignInState>(SignInController.new);

class SignInController extends Notifier<SignInState> {
  @override
  SignInState build() => const SignInState();

  Future<bool> submit(String email, String password) async {
    state = state.copyWith(busy: true, failed: false, offline: false, clearNotice: true);
    try {
      await ref.read(authControllerProvider.notifier).signIn(email.trim(), password);
      state = state.copyWith(busy: false);
      return true;
    } on ApiException {
      state = state.copyWith(busy: false, failed: true);
    } on ApiNetworkException {
      state = state.copyWith(busy: false, offline: true);
    }
    return false;
  }

  Future<void> social(String provider) async {
    state = state.copyWith(clearNotice: true, failed: false, offline: false);
    try {
      final device = await ref.read(deviceNameProvider.future);
      await ref.read(authApiProvider).social(provider, 'not-implemented', device);
    } on ApiException catch (e) {
      state = state.copyWith(socialNotice: e.message);
    } on ApiNetworkException {
      state = state.copyWith(offline: true);
    }
  }

  void clearFailure() => state = state.copyWith(failed: false, offline: false);
}
```

- [ ] **Step 6: `sign_in_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/auth/controller/sign_in_controller.dart';
import 'package:raajjepro/features/auth/presentation/widgets/auth_hero.dart';
import 'package:raajjepro/features/auth/presentation/widgets/social_sign_in_row.dart';
import 'package:raajjepro/shared/shared.dart';

/// Sign In (`Sign In.dc.html`; plan §Phase 3). States: default · failed
/// (one message, both values kept) · submitting (the button's own loading) ·
/// offline (inline notice with retry) · a third-party notice.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  static const routeName = '/sign-in';

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _reveal = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await ref.read(signInControllerProvider.notifier).submit(_email.text, _password.text);
    if (ok && mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final s = ref.watch(signInControllerProvider);
    final borderError = s.failed;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthHero(title: 'Welcome back', subtitle: 'Sign in to your RaajjePro account'),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.xxl, AppSpacing.xxl, AppSpacing.xxl, AppSpacing.xxxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (s.failed) _Notice.error("That email and password combination didn't work. Check both and try again."),
                  if (s.offline) _Notice.offline(onRetry: _submit),
                  if (s.socialNotice != null) _Notice.info(s.socialNotice!),
                  AppTextField(
                    key: const Key('signin-email'),
                    label: 'Email address',
                    controller: _email,
                    hint: 'aishath@example.mv',
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    errorText: borderError ? '' : null,
                    onChanged: (_) => ref.read(signInControllerProvider.notifier).clearFailure(),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    key: const Key('signin-password'),
                    label: 'Password',
                    controller: _password,
                    obscureText: !_reveal,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    errorText: borderError ? '' : null,
                    onChanged: (_) => ref.read(signInControllerProvider.notifier).clearFailure(),
                    suffix: Pressable(
                      semanticLabel: _reveal ? 'Hide password' : 'Show password',
                      onTap: () => setState(() => _reveal = !_reveal),
                      child: Icon(_reveal ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: colors.textSecondary, size: AppSizes.iconLg),
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: AppButton.text(label: 'Forgot password?', size: AppButtonSize.compact, onPressed: () => Navigator.of(context).pushNamed('/forgot-password')),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton.primary(label: s.busy ? 'Signing in…' : 'Sign In', loading: s.busy, expand: true, onPressed: s.busy ? null : _submit),
                  const SizedBox(height: AppSpacing.xxl),
                  Row(children: [
                    Expanded(child: Divider(color: colors.divider)),
                    Padding(padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.md), child: Text('or continue with', style: type.caption.copyWith(color: colors.textSecondary))),
                    Expanded(child: Divider(color: colors.divider)),
                  ]),
                  const SizedBox(height: AppSpacing.lg),
                  SocialSignInRow(onTap: (p) => ref.read(signInControllerProvider.notifier).social(p)),
                  const SizedBox(height: AppSpacing.xxl),
                  Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text("Don't have an account? ", style: type.body.copyWith(color: colors.textSecondary)),
                    AppButton.text(label: 'Create Account', size: AppButtonSize.compact, onPressed: () => Navigator.of(context).pushNamed('/register')),
                  ]),
                  AppButton.secondary(
                    label: 'Continue as Guest',
                    expand: true,
                    onPressed: () {
                      ref.read(authControllerProvider.notifier).continueAsGuest();
                      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Browsing, searching and viewing providers need no account. Sign in when you want to save, book or message.',
                    style: type.caption.copyWith(color: colors.textTertiary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The inline notices this screen family uses: error (red tint), offline
/// (with retry) and info (accent tint). Shared by Register and Verify Email.
class _Notice extends StatelessWidget {
  const _Notice._(this.text, this.kind, this.onRetry);
  factory _Notice.error(String text) => _Notice._(text, _NoticeKind.error, null);
  factory _Notice.info(String text) => _Notice._(text, _NoticeKind.info, null);
  factory _Notice.offline({required VoidCallback onRetry}) => _Notice._('No internet connection.', _NoticeKind.offline, onRetry);

  final String text;
  final _NoticeKind kind;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final (bg, border, fg) = switch (kind) {
      _NoticeKind.error => (colors.errorTint, colors.errorBorder, colors.errorText),
      _NoticeKind.info => (colors.accentTint, colors.accentBorder, colors.accentText),
      _NoticeKind.offline => (colors.warningTint, colors.warningBorder, colors.warningText),
    };
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.lg),
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsetsDirectional.all(AppSpacing.md),
          decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: AppRadius.circular(AppRadius.button)),
          child: Row(children: [
            Expanded(child: Text(text, style: type.secondary.copyWith(color: fg))),
            if (onRetry != null) AppButton.text(label: 'Try again', size: AppButtonSize.compact, onPressed: onRetry),
          ]),
        ),
      ),
    );
  }
}

enum _NoticeKind { error, info, offline }
```

Move `_Notice` into `frontend/lib/features/auth/presentation/widgets/inline_notice.dart` as a public `InlineNotice` so Register and Verify Email import it (same code, public name).

- [ ] **Step 7: Run** — `flutter test test/features/auth/sign_in_screen_test.dart && flutter analyze --no-pub` — Expected: PASS. (`AppTextField` with `errorText: ''` shows the red border without a message; if it renders an empty line, add a `hasError` boolean to `AppTextField` as an additive parameter instead.)

- [ ] **Step 8: Commit**

```bash
git add frontend/lib/features/auth frontend/test/features/auth
git commit -m "Sign In screen: prototype copy, one undifferentiated failure, own-button loading, stub third-party row, guest route"
```

---

### Task 5: Register screen

**Files:**
- Create: `frontend/lib/features/auth/controller/register_controller.dart`, `frontend/lib/features/auth/presentation/register_screen.dart`, `frontend/lib/features/auth/presentation/widgets/role_toggle.dart`, `frontend/lib/features/auth/presentation/widgets/phone_field.dart`
- Test: `frontend/test/features/auth/register_screen_test.dart`

**Reference:** `mockups/design-composer/Register.dc.html`. Title `Create account`, `Join RaajjePro — it only takes a minute`. `I want to…` two selectable cards: **Find Services** / `Book local providers` and **Offer Services** / `List my services`. Fields: `Full Name`, `Email Address`, `Phone Number` (dial-code prefix `🇲🇻 +960`, editable; when changed away from +960 a hint `Foreign numbers welcome — 6 to 15 digits.`), for providers `Business / Trade Name` with helper `The name customers will see on your listings` and the disclaimer `This creates your account only — you'll list services through Become a Provider after signing up.`, `Password`, `Confirm Password` (both with reveal), the terms row `I agree to RaajjePro's Terms of Service and Privacy Policy` (links to the Phase 23 placeholder routes `/legal/terms`, `/legal/privacy`), error `Please accept the terms to continue.`, CTA `Create Account` / `Create Provider Account`, footer `Already have an account? Sign In`. Duplicate email: `This email already has a RaajjePro account.` under the field with `Sign in` and `Reset password`. Duplicate phone: `This number belongs to a verified provider account. If it's yours, sign in instead — or use a different number.`

**Interfaces:**
- Produces: `RegisterScreen` (`routeName = '/register'`), `RoleToggle({required AccountRole value, required ValueChanged<AccountRole> onChanged})`, `PhoneField({required TextEditingController dialCode, required TextEditingController number, String? errorText, Widget? errorWidget})`, `registerControllerProvider` with `RegisterState { busy, fieldErrors: Map<String,String>, offline, termsError }` and `submit(RegisterRequest, {required bool acceptedTerms, required String confirmPassword}) → VerificationOutcome?`.
- Navigates to `VerifyEmailScreen.routeName` with `VerifyEmailArgs(email, outcome)` (defined in Task 6 — for this task navigate with `Navigator.pushReplacementNamed('/verify-email', arguments: {...})`; Task 6 replaces the map with the typed args).

- [ ] **Step 1: Failing test**

`frontend/test/features/auth/register_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/features/auth/presentation/register_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../core/auth/auth_controller_test.dart' show tokensJson, userJson;
import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

void main() {
  late FakeApiClient api;
  setUp(() => api = FakeApiClient());

  Future<void> pump(WidgetTester tester) => pumpScreen(
        tester,
        const RegisterScreen(),
        overrides: [apiClientProvider.overrideWithValue(api), tokenStoreProvider.overrideWithValue(InMemoryTokenStore()), deviceNameProvider.overrideWith((_) async => 'Test phone')],
        routes: {'/verify-email': (_) => const Scaffold(body: Text('VERIFY')), '/sign-in': (_) => const Scaffold(body: Text('SIGNIN')), '/forgot-password': (_) => const Scaffold(body: Text('FORGOT')), '/legal/terms': (_) => const Scaffold(body: Text('TERMS'))},
      );

  Future<void> fillValid(WidgetTester tester, {bool provider = false}) async {
    if (provider) await tester.tap(find.text('Offer Services'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('reg-name')), 'Aishath Naeema');
    await tester.enterText(find.byKey(const Key('reg-email')), 'aishath@example.mv');
    await tester.enterText(find.byKey(const Key('reg-phone')), '777 1234');
    if (provider) await tester.enterText(find.byKey(const Key('reg-business')), 'Rasheed Plumbing Services');
    await tester.enterText(find.byKey(const Key('reg-password')), 'seabreeze-24');
    await tester.enterText(find.byKey(const Key('reg-confirm')), 'seabreeze-24');
    await tester.tap(find.byKey(const Key('reg-terms')));
    await tester.pump();
  }

  final sent = {'status': 'sent', 'expiresAt': '2026-09-06T10:10:00.000Z', 'resendAvailableAt': '2026-09-06T10:01:00.000Z'};

  testWidgets('customer variant: no business field; submitting sends the role, +960 phone and acceptTerms, then goes to Verify Email', (tester) async {
    api.on('POST', '/v1/auth/register', (_) => {'user': userJson(), 'tokens': tokensJson(), 'verification': sent});
    await pump(tester);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.byKey(const Key('reg-business')), findsNothing);
    await fillValid(tester);
    await tester.tap(find.widgetWithText(AppButton, 'Create Account'));
    await settle(tester);
    final body = api.calls.single.body as Map;
    expect(body['role'], 'customer');
    expect(body['phone'], {'dialCode': '+960', 'number': '777 1234'});
    expect(body['acceptTerms'], isTrue);
    expect(body.containsKey('businessName'), isFalse);
    expect(find.text('VERIFY'), findsOneWidget);
  });

  testWidgets('provider variant adds exactly Business / Trade Name with the Become a Provider disclaimer and a provider CTA', (tester) async {
    api.on('POST', '/v1/auth/register', (_) => {'user': userJson(), 'tokens': tokensJson(), 'verification': sent});
    await pump(tester);
    await fillValid(tester, provider: true);
    expect(find.textContaining("you'll list services through Become a Provider"), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, 'Create Provider Account'));
    await settle(tester);
    final body = api.calls.single.body as Map;
    expect(body['role'], 'provider');
    expect(body['businessName'], 'Rasheed Plumbing Services');
  });

  testWidgets('client checks are UX only: mismatch and unaccepted terms block with inline copy and no request', (tester) async {
    await pump(tester);
    await fillValid(tester);
    await tester.enterText(find.byKey(const Key('reg-confirm')), 'different');
    await tester.tap(find.widgetWithText(AppButton, 'Create Account'));
    await settle(tester);
    expect(find.text("Passwords don't match"), findsOneWidget);
    expect(api.calls, isEmpty);
    await tester.enterText(find.byKey(const Key('reg-confirm')), 'seabreeze-24');
    await tester.tap(find.byKey(const Key('reg-terms'))); // untick
    await tester.tap(find.widgetWithText(AppButton, 'Create Account'));
    await settle(tester);
    expect(find.text('Please accept the terms to continue.'), findsOneWidget);
    expect(api.calls, isEmpty);
  });

  testWidgets('EMAIL_IN_USE renders under the email field with Sign in and Reset password routes', (tester) async {
    api.fail('POST', '/v1/auth/register', status: 409, code: 'EMAIL_IN_USE', details: [{'path': 'email', 'message': 'This email already has a RaajjePro account.'}]);
    await pump(tester);
    await fillValid(tester);
    await tester.tap(find.widgetWithText(AppButton, 'Create Account'));
    await settle(tester);
    expect(find.text('This email already has a RaajjePro account.'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Reset password'), findsOneWidget);
    expect(find.text('aishath@example.mv'), findsOneWidget); // value kept
    await tester.tap(find.text('Reset password'));
    await settle(tester);
    expect(find.text('FORGOT'), findsOneWidget);
  });

  testWidgets('PHONE_IN_USE renders under the phone field with the verified-provider copy; no check mark anywhere', (tester) async {
    api.fail('POST', '/v1/auth/register', status: 409, code: 'PHONE_IN_USE', details: [{'path': 'phone', 'message': 'This number belongs to a verified provider account.'}]);
    await pump(tester);
    await fillValid(tester);
    await tester.tap(find.widgetWithText(AppButton, 'Create Account'));
    await settle(tester);
    expect(find.textContaining('This number belongs to a verified provider account'), findsOneWidget);
    expect(find.textContaining('use a different number'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('VALIDATION_FAILED details map to their fields', (tester) async {
    api.fail('POST', '/v1/auth/register', status: 400, code: 'VALIDATION_FAILED', details: [{'path': 'password', 'message': 'Too short'}, {'path': 'phone', 'message': 'Phone number must be 6 to 15 digits'}]);
    await pump(tester);
    await fillValid(tester);
    await tester.tap(find.widgetWithText(AppButton, 'Create Account'));
    await settle(tester);
    expect(find.text('Too short'), findsOneWidget);
    expect(find.text('Phone number must be 6 to 15 digits'), findsOneWidget);
  });

  testWidgets('a foreign dial code shows the welcome hint; offline shows the inline notice', (tester) async {
    api.offline('POST', '/v1/auth/register');
    await pump(tester);
    await fillValid(tester);
    await tester.enterText(find.byKey(const Key('reg-dial')), '+44');
    await tester.pump();
    expect(find.text('Foreign numbers welcome — 6 to 15 digits.'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, 'Create Account'));
    await settle(tester);
    expect(find.text('No internet connection.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to fail** — Expected: FAIL.

- [ ] **Step 3: `role_toggle.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// `I want to…` — two selectable cards (`Register.dc.html`). Selecting Offer
/// Services adds one field; it does not make anyone a provider.
class RoleToggle extends StatelessWidget {
  const RoleToggle({required this.value, required this.onChanged, super.key});
  final AccountRole value;
  final ValueChanged<AccountRole> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    Widget card(AccountRole role, IconData icon, String title, String sub) {
      final selected = role == value;
      return Expanded(
        child: Pressable(
          semanticLabel: '$title, $sub${selected ? ', selected' : ''}',
          onTap: () => onChanged(role),
          child: AnimatedContainer(
            duration: context.motion.fast,
            padding: const EdgeInsetsDirectional.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: selected ? colors.accentTint : colors.surface,
              borderRadius: AppRadius.circular(AppRadius.card),
              border: Border.all(color: selected ? colors.primary : colors.border, width: selected ? AppSizes.selectedStroke : AppSizes.inputStroke),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: selected ? colors.primary : colors.textSecondary, size: AppSizes.iconLg),
              const SizedBox(height: AppSpacing.sm),
              Text(title, style: type.bodyStrong.copyWith(color: selected ? colors.primaryPressed : colors.ink)),
              Text(sub, style: type.caption.copyWith(color: colors.textSecondary)),
            ]),
          ),
        ),
      );
    }
    return Row(children: [
      card(AccountRole.customer, Icons.search_rounded, 'Find Services', 'Book local providers'),
      const SizedBox(width: AppSpacing.md),
      card(AccountRole.provider, Icons.handyman_outlined, 'Offer Services', 'List my services'),
    ]);
  }
}
```

- [ ] **Step 4: `phone_field.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// Dial code + national number (`Register.dc.html`; plan §Phase 3). `+960`
/// is the default, foreign codes are welcome, 6–15 digits. The number is
/// shown as typed and **never** with a check mark or the word verified —
/// nothing in this system verifies it. [errorWidget] lets the caller render
/// the duplicate-phone copy with its inline sign-in route under the field.
class PhoneField extends StatelessWidget {
  const PhoneField({required this.dialCode, required this.number, super.key, this.errorText, this.errorWidget, this.onChanged});
  final TextEditingController dialCode;
  final TextEditingController number;
  final String? errorText;
  final Widget? errorWidget;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final foreign = dialCode.text.trim() != '+960' && dialCode.text.trim().length > 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        SizedBox(
          width: 104,
          child: AppTextField(
            key: const Key('reg-dial'),
            label: 'Code',
            controller: dialCode,
            keyboardType: TextInputType.phone,
            prefixIcon: foreign ? Icons.public : null,
            hint: '+960',
            onChanged: (_) => onChanged?.call(),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: AppTextField(
            key: const Key('reg-phone'),
            label: 'Phone Number',
            controller: number,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            hint: '777 1234',
            errorText: errorText,
            helper: foreign ? 'Foreign numbers welcome — 6 to 15 digits.' : null,
            onChanged: (_) => onChanged?.call(),
          ),
        ),
      ]),
      if (errorWidget != null) Padding(padding: const EdgeInsetsDirectional.only(top: AppSpacing.xs), child: DefaultTextStyle(style: type.caption.copyWith(color: colors.errorText), child: errorWidget!)),
    ]);
  }
}
```

(When `dialCode.text` is `+960` show the 🇲🇻 flag as a leading `Text` instead of an icon if `AppTextField.prefixIcon` only takes `IconData` — a small `Row` with the flag glyph before the field is acceptable.)

- [ ] **Step 5: `register_controller.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';

class RegisterState {
  const RegisterState({this.busy = false, this.fieldErrors = const {}, this.offline = false});
  final bool busy;
  /// path → message, from the API's details. `email` and `phone` get their own
  /// rich rendering; everything else renders as the field's errorText.
  final Map<String, String> fieldErrors;
  final bool offline;
  RegisterState copyWith({bool? busy, Map<String, String>? fieldErrors, bool? offline}) =>
      RegisterState(busy: busy ?? this.busy, fieldErrors: fieldErrors ?? this.fieldErrors, offline: offline ?? this.offline);
}

final registerControllerProvider = NotifierProvider<RegisterController, RegisterState>(RegisterController.new);

class RegisterController extends Notifier<RegisterState> {
  @override
  RegisterState build() => const RegisterState();

  /// Client checks here are UX only (root CLAUDE.md invariant 4): the server
  /// re-validates everything. Returns the verification outcome on success.
  Future<VerificationOutcome?> submit(RegisterRequest request, {required bool acceptedTerms, required String confirmPassword}) async {
    final local = <String, String>{};
    if (request.password != confirmPassword) local['confirmPassword'] = "Passwords don't match";
    if (!acceptedTerms) local['acceptTerms'] = 'Please accept the terms to continue.';
    if (local.isNotEmpty) {
      state = state.copyWith(fieldErrors: local);
      return null;
    }
    state = state.copyWith(busy: true, fieldErrors: const {}, offline: false);
    try {
      final outcome = await ref.read(authControllerProvider.notifier).register(request);
      state = state.copyWith(busy: false);
      return outcome;
    } on ApiException catch (e) {
      final errors = <String, String>{};
      for (final f in e.fieldErrors) {
        errors[f.path.split('.').first] = f.message;
      }
      if (errors.isEmpty) errors['form'] = e.message;
      state = state.copyWith(busy: false, fieldErrors: errors);
    } on ApiNetworkException {
      state = state.copyWith(busy: false, offline: true);
    }
    return null;
  }

  void clear(String path) {
    if (!state.fieldErrors.containsKey(path)) return;
    state = state.copyWith(fieldErrors: Map.of(state.fieldErrors)..remove(path));
  }
}
```

- [ ] **Step 6: `register_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/auth/controller/register_controller.dart';
import 'package:raajjepro/features/auth/presentation/widgets/auth_hero.dart';
import 'package:raajjepro/features/auth/presentation/widgets/inline_notice.dart';
import 'package:raajjepro/features/auth/presentation/widgets/phone_field.dart';
import 'package:raajjepro/features/auth/presentation/widgets/role_toggle.dart';
import 'package:raajjepro/shared/shared.dart';

/// Register (`Register.dc.html`; plan §Phase 3, §1 "provider variant adds
/// Business / Trade Name"). States: default · field errors (VALIDATION_FAILED,
/// EMAIL_IN_USE with routes, PHONE_IN_USE with its copy) · submitting ·
/// offline. Registering as Offer Services creates an account only; Become a
/// Provider (Phase 6a) is what sets someone up.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  static const routeName = '/register';

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  AccountRole _role = AccountRole.customer;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _dial = TextEditingController(text: '+960');
  final _phone = TextEditingController();
  final _business = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _reveal1 = false, _reveal2 = false, _terms = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _dial, _phone, _business, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final device = 'Unknown device'; // replaced by deviceNameProvider below
    final request = RegisterRequest(
      role: _role, fullName: _name.text, email: _email.text, dialCode: _dial.text, number: _phone.text,
      password: _password.text, businessName: _role == AccountRole.provider ? _business.text : null,
      deviceName: await ref.read(deviceNameProvider.future).catchError((_) => device),
    );
    final outcome = await ref.read(registerControllerProvider.notifier).submit(request, acceptedTerms: _terms, confirmPassword: _confirm.text);
    if (outcome != null && mounted) {
      Navigator.of(context).pushReplacementNamed('/verify-email', arguments: {'email': _email.text.trim(), 'status': outcome.status.name, 'resendAvailableAt': outcome.resendAvailableAt.toIso8601String()});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final s = ref.watch(registerControllerProvider);
    final ctrl = ref.read(registerControllerProvider.notifier);
    final isProvider = _role == AccountRole.provider;

    Widget reveal(bool on, VoidCallback toggle) => Pressable(
      semanticLabel: on ? 'Hide password' : 'Show password', onTap: toggle,
      child: Icon(on ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: colors.textSecondary, size: AppSizes.iconLg),
    );

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const AuthHero(title: 'Create account', subtitle: 'Join RaajjePro — it only takes a minute'),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.xxl, AppSpacing.xxl, AppSpacing.xxl, AppSpacing.xxxl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (s.offline) InlineNotice.offline(onRetry: _submit),
              if (s.fieldErrors['form'] != null) InlineNotice.error(s.fieldErrors['form']!),
              Text('I want to…', style: type.bodyStrong),
              const SizedBox(height: AppSpacing.sm),
              RoleToggle(value: _role, onChanged: (r) => setState(() => _role = r)),
              const SizedBox(height: AppSpacing.xl),
              AppTextField(key: const Key('reg-name'), label: 'Full Name', controller: _name, textCapitalization: TextCapitalization.words, autofillHints: const [AutofillHints.name], errorText: s.fieldErrors['fullName'], onChanged: (_) => ctrl.clear('fullName')),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(key: const Key('reg-email'), label: 'Email Address', controller: _email, keyboardType: TextInputType.emailAddress, autocorrect: false, autofillHints: const [AutofillHints.email], hint: 'aishath@example.mv',
                errorText: s.fieldErrors['email'], onChanged: (_) => ctrl.clear('email')),
              if (s.fieldErrors['email'] != null && s.fieldErrors['email']!.contains('already'))
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  AppButton.text(label: 'Sign in', size: AppButtonSize.compact, onPressed: () => Navigator.of(context).pushReplacementNamed('/sign-in')),
                  Text('·', style: type.caption.copyWith(color: colors.textSecondary)),
                  AppButton.text(label: 'Reset password', size: AppButtonSize.compact, onPressed: () => Navigator.of(context).pushNamed('/forgot-password')),
                ]),
              const SizedBox(height: AppSpacing.lg),
              PhoneField(
                dialCode: _dial, number: _phone,
                errorText: s.fieldErrors['phone'] != null && !s.fieldErrors['phone']!.contains('verified provider') ? s.fieldErrors['phone'] : null,
                errorWidget: s.fieldErrors['phone'] != null && s.fieldErrors['phone']!.contains('verified provider')
                    ? Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                        const Text('This number belongs to a verified provider account. If it\'s yours, '),
                        AppButton.text(label: 'sign in', size: AppButtonSize.compact, onPressed: () => Navigator.of(context).pushReplacementNamed('/sign-in')),
                        const Text(' instead — or use a different number.'),
                      ])
                    : null,
                onChanged: () { ctrl.clear('phone'); setState(() {}); },
              ),
              if (isProvider) ...[
                const SizedBox(height: AppSpacing.lg),
                AppTextField(key: const Key('reg-business'), label: 'Business / Trade Name', controller: _business, helper: 'The name customers will see on your listings', textCapitalization: TextCapitalization.words, errorText: s.fieldErrors['businessName'], onChanged: (_) => ctrl.clear('businessName')),
                const SizedBox(height: AppSpacing.sm),
                InlineNotice.info("This creates your account only — you'll list services through Become a Provider after signing up."),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppTextField(key: const Key('reg-password'), label: 'Password', controller: _password, obscureText: !_reveal1, autofillHints: const [AutofillHints.newPassword], helper: 'At least 8 characters', errorText: s.fieldErrors['password'], onChanged: (_) => ctrl.clear('password'), suffix: reveal(_reveal1, () => setState(() => _reveal1 = !_reveal1))),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(key: const Key('reg-confirm'), label: 'Confirm Password', controller: _confirm, obscureText: !_reveal2, errorText: s.fieldErrors['confirmPassword'], onChanged: (_) => ctrl.clear('confirmPassword'), suffix: reveal(_reveal2, () => setState(() => _reveal2 = !_reveal2))),
              const SizedBox(height: AppSpacing.xl),
              Pressable(
                key: const Key('reg-terms'),
                semanticLabel: 'I agree to the Terms of Service and Privacy Policy${_terms ? ', checked' : ', not checked'}',
                onTap: () { setState(() => _terms = !_terms); ctrl.clear('acceptTerms'); },
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: AppSizes.checkbox, height: AppSizes.checkbox,
                    decoration: BoxDecoration(color: _terms ? colors.primary : colors.surface, borderRadius: AppRadius.circular(AppRadius.xs), border: Border.all(color: _terms ? colors.primary : colors.neutralBorder, width: AppSizes.inputStroke)),
                    child: _terms ? Icon(Icons.check_rounded, size: AppSizes.iconMd, color: colors.onPrimary) : null,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text("I agree to RaajjePro's ", style: type.secondary),
                    AppButton.text(label: 'Terms of Service', size: AppButtonSize.compact, onPressed: () => Navigator.of(context).pushNamed('/legal/terms')),
                    Text(' and ', style: type.secondary),
                    AppButton.text(label: 'Privacy Policy', size: AppButtonSize.compact, onPressed: () => Navigator.of(context).pushNamed('/legal/privacy')),
                  ])),
                ]),
              ),
              if (s.fieldErrors['acceptTerms'] != null) Padding(padding: const EdgeInsetsDirectional.only(top: AppSpacing.xs), child: Text(s.fieldErrors['acceptTerms']!, style: type.caption.copyWith(color: colors.errorText))),
              const SizedBox(height: AppSpacing.xl),
              AppButton.primary(label: isProvider ? 'Create Provider Account' : 'Create Account', loading: s.busy, expand: true, onPressed: s.busy ? null : _submit),
              const SizedBox(height: AppSpacing.lg),
              Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('Already have an account? ', style: type.body.copyWith(color: colors.textSecondary)),
                AppButton.text(label: 'Sign In', size: AppButtonSize.compact, onPressed: () => Navigator.of(context).pushReplacementNamed('/sign-in')),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
```

(Import `deviceNameProvider` from `core/auth/device_name.dart`. The `/legal/*` routes are Phase 23's; until they exist the Task 7 route table maps them to a clearly-marked placeholder page — "Placeholder — legal text pending review" — never invented policy text.)

- [ ] **Step 7: Run** — `flutter test test/features/auth && flutter analyze --no-pub` — Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add frontend/lib/features/auth frontend/test/features/auth
git commit -m "Register screen: role toggle, +960 phone with foreign hint, field-level duplicate email and phone, provider disclaimer"
```

---

### Task 6: Verify Email screen — six boxes, two timers, every state

**Files:**
- Create: `frontend/lib/features/auth/presentation/widgets/otp_code_entry.dart`, `frontend/lib/features/auth/presentation/widgets/countdown_text.dart`, `frontend/lib/features/auth/controller/verify_email_controller.dart`, `frontend/lib/features/auth/presentation/verify_email_screen.dart`, `frontend/lib/core/clock.dart`
- Test: `frontend/test/features/auth/verify_email_screen_test.dart`

**Reference:** `mockups/design-composer/Verify Email.dc.html`. Back control; hero icon; `Verify your email`; `We emailed a 6-digit code to` **{email}**; `Not your address? Change it`; six boxes (auto-advance, backspace retreats); wrong-code banner `That code isn't right — N attempts left before it needs a fresh send.`; invalidated banner `That code has been invalidated after 5 incorrect attempts. Request a fresh one to continue.` with `Send a fresh code`; resent banner `A new code is on its way to your inbox.`; `Verify Email` / `Checking…`; `Resend code in m:ss` then `Resend code`; rate-limited card `A short wait before the next code` / `You've requested several codes in a row. You can send another in` **m:ss** with the note `Codes are limited to 3 per address every 15 minutes, and 5 per account each hour. Codes already in your inbox still work until they expire.`; success card `Email verified` / `You're all set — booking, enquiries and messaging are now open to you.` / `Continue`; footer `Booking, enquiring and messaging need a verified email. Browsing doesn't — you can finish this any time.` / `I'll do this later`. Plus, per the spec, a **send_failed** state for `suppressed`/`failed`: `We couldn't send a code to this address. Check it's right, or try again in a moment.`

**Interfaces:**
- Produces: `VerifyEmailScreen` (`routeName = '/verify-email'`, takes `VerifyEmailArgs { email, purpose: OtpPurpose (verifyEmail | changeEmail), initialStatus: VerificationStatus?, resendAvailableAt: DateTime? }` from route arguments — a typed class, with a `fromRouteArguments(Object?)` that also accepts the Task 5 map); `OtpCodeEntry({required ValueChanged<String> onChanged, required ValueChanged<String> onCompleted, bool enabled, bool error})`; `CountdownText({required DateTime until, required String Function(String mmss) format})`; `clockProvider` (`Provider<DateTime Function()>`); `verifyEmailControllerProvider(args)` (a `NotifierProvider.family`) with `VerifyEmailState { mode: entry|resent|wrong|invalidated|rateLimited|success|sendFailed, checking, attemptsRemaining, resendAvailableAt, rateLimitedUntil }`, methods `verify(code)`, `resend()`, `codeChanged()`.
- On success for `verifyEmail`: `AuthController.markVerified()`; for `changeEmail`: `AuthController.applyUser(await api.confirmEmailChange(code))` (Task 9 uses this path).

- [ ] **Step 1: `core/clock.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Injected time, so countdowns are tested by overriding this rather than by
/// waiting. Widgets still tick with a `Timer.periodic`; only "now" comes here.
final clockProvider = Provider<DateTime Function()>((_) => DateTime.now);
```

- [ ] **Step 2: Failing test**

`frontend/test/features/auth/verify_email_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/features/auth/presentation/verify_email_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

void main() {
  late FakeApiClient api;
  var now = DateTime.utc(2026, 9, 6, 10);
  setUp(() {
    api = FakeApiClient();
    now = DateTime.utc(2026, 9, 6, 10);
  });

  Future<void> pump(WidgetTester tester, {VerificationStatus? status, DateTime? resendAt}) => pumpScreen(
        tester,
        VerifyEmailScreen(args: VerifyEmailArgs(email: 'aishath@example.mv', purpose: OtpPurpose.verifyEmail, initialStatus: status, resendAvailableAt: resendAt ?? now.add(const Duration(seconds: 47)))),
        overrides: [apiClientProvider.overrideWithValue(api), tokenStoreProvider.overrideWithValue(InMemoryTokenStore()), clockProvider.overrideWithValue(() => now)],
        routes: {'/': (_) => const Scaffold(body: Text('HOME')), '/account/change-email': (_) => const Scaffold(body: Text('CHANGE'))},
      );

  Future<void> typeCode(WidgetTester tester, String code) async {
    for (var i = 0; i < 6; i++) {
      await tester.enterText(find.byKey(Key('otp-$i')), code[i]);
      await tester.pump();
    }
  }

  testWidgets('entry: the address in full, email-only copy, a resend countdown that is not the rate-limit clock, a disabled verify until six digits', (tester) async {
    await pump(tester);
    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.text('aishath@example.mv'), findsOneWidget);
    expect(find.textContaining('SMS'), findsNothing);
    expect(find.text('Resend code in 0:47'), findsOneWidget);
    expect(find.text('A short wait before the next code'), findsNothing);
    final verify = tester.widget<AppButton>(find.widgetWithText(AppButton, 'Verify Email'));
    expect(verify.onPressed, isNull);
    await typeCode(tester, '482913');
    expect(tester.widget<AppButton>(find.widgetWithText(AppButton, 'Verify Email')).onPressed, isNotNull);
    expect(find.textContaining("Browsing doesn't"), findsOneWidget);
    expect(find.text("I'll do this later"), findsOneWidget);
  });

  testWidgets('the countdown reaches zero and becomes a Resend button; resend shows the resent banner', (tester) async {
    api.on('POST', '/v1/auth/verify-email/send', (_) => {'status': 'sent', 'expiresAt': now.add(const Duration(minutes: 10)).toIso8601String(), 'resendAvailableAt': now.add(const Duration(seconds: 60)).toIso8601String()});
    await pump(tester);
    now = now.add(const Duration(seconds: 48));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Resend code'), findsOneWidget);
    await tester.tap(find.text('Resend code'));
    await settle(tester);
    expect(find.text('A new code is on its way to your inbox.'), findsOneWidget);
    expect(find.text('Resend code in 1:00'), findsOneWidget);
  });

  testWidgets('wrong code shows attempts remaining; invalidated disables the boxes and offers a fresh send', (tester) async {
    api.fail('POST', '/v1/auth/verify-email/confirm', status: 422, code: 'OTP_INCORRECT', details: {'attemptsRemaining': 2});
    await pump(tester);
    await typeCode(tester, '000000');
    await tester.tap(find.widgetWithText(AppButton, 'Verify Email'));
    await settle(tester);
    expect(find.text("That code isn't right — 2 attempts left before it needs a fresh send."), findsOneWidget);
    api.fail('POST', '/v1/auth/verify-email/confirm', status: 422, code: 'OTP_INVALIDATED');
    await typeCode(tester, '000001');
    await tester.tap(find.widgetWithText(AppButton, 'Verify Email'));
    await settle(tester);
    expect(find.textContaining('invalidated after 5 incorrect attempts'), findsOneWidget);
    expect(find.text('Send a fresh code'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('otp-0'))).enabled, isFalse);
  });

  testWidgets('OTP_RATE_LIMITED renders the wait with its own clock and both limits named; expiry returns to entry', (tester) async {
    api.fail('POST', '/v1/auth/verify-email/send', status: 429, code: 'OTP_RATE_LIMITED', details: {'retryAfterSeconds': 272, 'limit': 'address'});
    await pump(tester, resendAt: now);
    await tester.tap(find.text('Resend code'));
    await settle(tester);
    expect(find.text('A short wait before the next code'), findsOneWidget);
    expect(find.text('4:32'), findsOneWidget);
    expect(find.textContaining('3 per address every 15 minutes, and 5 per account each hour'), findsOneWidget);
    now = now.add(const Duration(seconds: 273));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('A short wait before the next code'), findsNothing);
    expect(find.byKey(const Key('otp-0')), findsOneWidget);
  });

  testWidgets('success card, then Continue goes home; the auth state is marked verified', (tester) async {
    api.on('POST', '/v1/auth/verify-email/confirm', (_) => {'emailVerified': true});
    await pump(tester);
    await typeCode(tester, '482913');
    await tester.tap(find.widgetWithText(AppButton, 'Verify Email'));
    await settle(tester);
    expect(find.text('Email verified'), findsOneWidget);
    expect(find.textContaining('booking, enquiries and messaging are now open'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await settle(tester);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('a suppressed or failed send is shown honestly, never as sent', (tester) async {
    await pump(tester, status: VerificationStatus.suppressed);
    expect(find.textContaining("couldn't send a code to this address"), findsOneWidget);
    expect(find.text('A new code is on its way to your inbox.'), findsNothing);
  });

  testWidgets('Not your address? Change it routes to change email; I\'ll do this later goes home', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Not your address? Change it'));
    await settle(tester);
    expect(find.text('CHANGE'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.text("I'll do this later"));
    await settle(tester);
    expect(find.text('HOME'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run to fail** — Expected: FAIL.

- [ ] **Step 4: `countdown_text.dart`**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/clock.dart';

/// `m:ss` until [until], ticking once a second from the injected clock.
/// Calls [onDone] once when it reaches zero. Two of these on Verify Email are
/// two different timers — resend cooldown and rate-limit wait — and are never
/// rendered as one.
class CountdownText extends ConsumerStatefulWidget {
  const CountdownText({required this.until, required this.format, super.key, this.onDone, this.style});
  final DateTime until;
  final String Function(String mmss) format;
  final VoidCallback? onDone;
  final TextStyle? style;

  static String mmss(Duration d) {
    final s = d.inSeconds < 0 ? 0 : d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  ConsumerState<CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends ConsumerState<CountdownText> {
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final remaining = widget.until.difference(ref.read(clockProvider)());
    if (remaining.inSeconds <= 0 && !_done) {
      _done = true;
      widget.onDone?.call();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.until.difference(ref.watch(clockProvider)());
    return Text(widget.format(CountdownText.mmss(remaining)), style: widget.style);
  }
}
```

- [ ] **Step 5: `otp_code_entry.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:raajjepro/core/theme/app_theme.dart';

/// Six one-digit boxes (`Verify Email.dc.html`): typing advances, backspace
/// on an empty box retreats, a paste of six digits fills all. Error paints
/// every border red; disabled greys the fill (the invalidated state).
class OtpCodeEntry extends StatefulWidget {
  const OtpCodeEntry({required this.onChanged, required this.onCompleted, super.key, this.enabled = true, this.error = false, this.clearToken = 0});
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onCompleted;
  final bool enabled;
  final bool error;
  /// Bump to clear every box (after a wrong attempt).
  final int clearToken;

  @override
  State<OtpCodeEntry> createState() => _OtpCodeEntryState();
}

class _OtpCodeEntryState extends State<OtpCodeEntry> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focus = List.generate(6, (_) => FocusNode());

  String get _code => _controllers.map((c) => c.text).join();

  @override
  void didUpdateWidget(OtpCodeEntry old) {
    super.didUpdateWidget(old);
    if (old.clearToken != widget.clearToken) {
      for (final c in _controllers) {
        c.clear();
      }
      _focus.first.requestFocus();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focus) {
      f.dispose();
    }
    super.dispose();
  }

  void _changed(int i, String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 1) {
      for (var j = 0; j < 6; j++) {
        _controllers[j].text = j < digits.length ? digits[j] : '';
      }
      _focus[digits.length.clamp(0, 5)].requestFocus();
    } else {
      _controllers[i].text = digits;
      if (digits.isNotEmpty && i < 5) _focus[i + 1].requestFocus();
    }
    widget.onChanged(_code);
    if (_code.length == 6) widget.onCompleted(_code);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Semantics(
      container: true,
      label: '6-digit verification code',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 6; i++)
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.xxs),
              child: SizedBox(
                width: 48,
                height: 58,
                child: KeyboardListener(
                  focusNode: FocusNode(skipTraversal: true),
                  onKeyEvent: (e) {
                    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.backspace && _controllers[i].text.isEmpty && i > 0) {
                      _focus[i - 1].requestFocus();
                    }
                  },
                  child: TextField(
                    key: Key('otp-$i'),
                    controller: _controllers[i],
                    focusNode: _focus[i],
                    enabled: widget.enabled,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: type.stat.copyWith(color: colors.ink),
                    onChanged: (v) => _changed(i, v),
                    decoration: InputDecoration(
                      counterText: '',
                      contentPadding: EdgeInsets.zero,
                      filled: true,
                      fillColor: widget.enabled ? colors.surface : colors.surfaceMuted,
                      semanticCounterText: 'Digit ${i + 1}',
                      enabledBorder: OutlineInputBorder(borderRadius: AppRadius.circular(AppRadius.input), borderSide: BorderSide(color: widget.error ? colors.errorBorder : colors.border, width: AppSizes.inputStroke)),
                      focusedBorder: OutlineInputBorder(borderRadius: AppRadius.circular(AppRadius.input), borderSide: BorderSide(color: colors.primary, width: AppSizes.inputStroke)),
                      disabledBorder: OutlineInputBorder(borderRadius: AppRadius.circular(AppRadius.input), borderSide: BorderSide(color: colors.errorBorder, width: AppSizes.inputStroke)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: `verify_email_controller.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/clock.dart';

enum OtpPurpose { verifyEmail, changeEmail }

enum VerifyMode { entry, resent, wrong, invalidated, rateLimited, success, sendFailed, offline }

class VerifyEmailArgs {
  const VerifyEmailArgs({required this.email, required this.purpose, this.initialStatus, this.resendAvailableAt});
  final String email;
  final OtpPurpose purpose;
  final VerificationStatus? initialStatus;
  final DateTime? resendAvailableAt;

  /// Accepts the typed args or the map Register pushed before this class existed.
  static VerifyEmailArgs fromRouteArguments(Object? a) {
    if (a is VerifyEmailArgs) return a;
    final m = a as Map<String, dynamic>;
    return VerifyEmailArgs(
      email: m['email'] as String,
      purpose: m['purpose'] == 'changeEmail' ? OtpPurpose.changeEmail : OtpPurpose.verifyEmail,
      initialStatus: VerificationStatus.values.asNameMap()[m['status'] as String?],
      resendAvailableAt: m['resendAvailableAt'] is String ? DateTime.parse(m['resendAvailableAt'] as String) : null,
    );
  }
}

class VerifyEmailState {
  const VerifyEmailState({required this.mode, this.checking = false, this.attemptsRemaining, required this.resendAvailableAt, this.rateLimitedUntil, this.clearToken = 0});
  final VerifyMode mode;
  final bool checking;
  final int? attemptsRemaining;
  final DateTime resendAvailableAt;
  final DateTime? rateLimitedUntil;
  final int clearToken;

  VerifyEmailState copyWith({VerifyMode? mode, bool? checking, int? attemptsRemaining, DateTime? resendAvailableAt, DateTime? rateLimitedUntil, int? clearToken}) => VerifyEmailState(
    mode: mode ?? this.mode, checking: checking ?? this.checking, attemptsRemaining: attemptsRemaining ?? this.attemptsRemaining,
    resendAvailableAt: resendAvailableAt ?? this.resendAvailableAt, rateLimitedUntil: rateLimitedUntil ?? this.rateLimitedUntil, clearToken: clearToken ?? this.clearToken,
  );
}

final verifyEmailControllerProvider = NotifierProvider.family<VerifyEmailController, VerifyEmailState, VerifyEmailArgs>(VerifyEmailController.new);

/// Drives Verify Email (spec §8). Two timers are two fields: the resend
/// cooldown (advisory, 60 s after each send) and the rate-limit wait (the
/// server's `retryAfterSeconds`). Modes map one-to-one onto the prototype.
class VerifyEmailController extends FamilyNotifier<VerifyEmailState, VerifyEmailArgs> {
  @override
  VerifyEmailState build(VerifyEmailArgs args) {
    final now = ref.read(clockProvider)();
    final failed = args.initialStatus == VerificationStatus.suppressed || args.initialStatus == VerificationStatus.failed;
    return VerifyEmailState(mode: failed ? VerifyMode.sendFailed : VerifyMode.entry, resendAvailableAt: args.resendAvailableAt ?? now);
  }

  void codeChanged() {
    if (state.mode == VerifyMode.wrong || state.mode == VerifyMode.resent || state.mode == VerifyMode.offline) state = state.copyWith(mode: VerifyMode.entry);
  }

  void rateLimitEnded() {
    if (state.mode == VerifyMode.rateLimited) state = state.copyWith(mode: VerifyMode.entry);
  }

  Future<void> verify(String code) async {
    state = state.copyWith(checking: true);
    try {
      final api = ref.read(authApiProvider);
      if (arg.purpose == OtpPurpose.verifyEmail) {
        await api.confirmVerification(code);
        ref.read(authControllerProvider.notifier).markVerified();
      } else {
        ref.read(authControllerProvider.notifier).applyUser(await api.confirmEmailChange(code));
      }
      state = state.copyWith(checking: false, mode: VerifyMode.success);
    } on ApiException catch (e) {
      final next = switch (e.code) {
        'OTP_INVALIDATED' => VerifyMode.invalidated,
        'OTP_EXPIRED' => VerifyMode.invalidated,
        _ => VerifyMode.wrong,
      };
      state = state.copyWith(checking: false, mode: next, attemptsRemaining: e.attemptsRemaining, clearToken: state.clearToken + 1);
    } on ApiNetworkException {
      state = state.copyWith(checking: false, mode: VerifyMode.offline);
    }
  }

  Future<void> resend() async {
    final now = ref.read(clockProvider)();
    try {
      final api = ref.read(authApiProvider);
      final outcome = arg.purpose == OtpPurpose.verifyEmail ? await api.sendVerification() : throw StateError('change-email resend goes through ChangeEmail (Task 9)');
      state = state.copyWith(
        mode: outcome.status == VerificationStatus.sent ? VerifyMode.resent : VerifyMode.sendFailed,
        resendAvailableAt: outcome.resendAvailableAt, attemptsRemaining: null, clearToken: state.clearToken + 1,
      );
    } on ApiException catch (e) {
      if (e.code == 'OTP_RATE_LIMITED') {
        state = state.copyWith(mode: VerifyMode.rateLimited, rateLimitedUntil: now.add(Duration(seconds: e.retryAfterSeconds ?? 60)));
      } else if (e.code == 'EMAIL_ALREADY_VERIFIED') {
        ref.read(authControllerProvider.notifier).markVerified();
        state = state.copyWith(mode: VerifyMode.success);
      } else {
        state = state.copyWith(mode: VerifyMode.sendFailed);
      }
    } on ApiNetworkException {
      state = state.copyWith(mode: VerifyMode.offline);
    }
  }
}
```

(Task 9's change-email flow passes a `resend` override; simplest: add an optional `Future<VerificationOutcome> Function()? resendOverride` to `VerifyEmailArgs`, used when non-null. Add it now so Task 9 needs no change here.)

- [ ] **Step 7: `verify_email_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/auth/controller/verify_email_controller.dart';
import 'package:raajjepro/features/auth/presentation/widgets/countdown_text.dart';
import 'package:raajjepro/features/auth/presentation/widgets/inline_notice.dart';
import 'package:raajjepro/features/auth/presentation/widgets/otp_code_entry.dart';
import 'package:raajjepro/shared/shared.dart';

export 'package:raajjepro/features/auth/controller/verify_email_controller.dart' show VerifyEmailArgs, OtpPurpose;

/// Verify Email (`Verify Email.dc.html`; plan §Phase 3). Email-only, always.
/// States: entry · resent · wrong_code · code_invalidated · rate_limited ·
/// success · send_failed · offline. Two timers, two clocks.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({required this.args, super.key});
  static const routeName = '/verify-email';
  final VerifyEmailArgs args;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  String _code = '';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final provider = verifyEmailControllerProvider(widget.args);
    final s = ref.watch(provider);
    final ctrl = ref.read(provider.notifier);
    final now = ref.watch(clockProvider)();
    final isChange = widget.args.purpose == OtpPurpose.changeEmail;

    void goHome() => Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);

    return Scaffold(
      body: Column(children: [
        AppHeader.page(title: '', onBack: () => Navigator.of(context).maybePop()),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.xxl, AppSpacing.md, AppSpacing.xxl, AppSpacing.xxxl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Container(width: 96, height: 96, decoration: BoxDecoration(color: colors.accentTint, borderRadius: AppRadius.circular(AppRadius.sheet)), alignment: Alignment.center, child: Icon(Icons.mail_outline_rounded, size: 40, color: colors.primary))),
              const SizedBox(height: AppSpacing.lg),
              Text(isChange ? 'Verify your new email' : 'Verify your email', style: type.screenTitle, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              Text.rich(TextSpan(text: 'We emailed a 6-digit code to\n', style: type.body.copyWith(color: colors.textSecondary), children: [TextSpan(text: widget.args.email, style: type.bodyStrong.copyWith(color: colors.ink, fontWeight: FontWeight.w800))]), textAlign: TextAlign.center),
              if (!isChange) Center(child: AppButton.text(label: 'Not your address? Change it', size: AppButtonSize.compact, onPressed: () => Navigator.of(context).pushNamed('/account/change-email'))),
              const SizedBox(height: AppSpacing.xl),

              if (s.mode == VerifyMode.rateLimited && s.rateLimitedUntil != null) ...[
                AppCard(
                  child: Column(children: [
                    Container(width: 64, height: 64, decoration: BoxDecoration(color: colors.warningTint, shape: BoxShape.circle), alignment: Alignment.center, child: Icon(Icons.schedule_rounded, color: colors.warning, size: 28)),
                    const SizedBox(height: AppSpacing.md),
                    Text('A short wait before the next code', style: type.sectionHeading, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.sm),
                    Text("You've requested several codes in a row. You can send another in", style: type.secondary.copyWith(color: colors.textSecondary), textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.sm),
                    CountdownText(until: s.rateLimitedUntil!, format: (t) => t, style: type.stat.copyWith(color: colors.warningText, fontSize: 30), onDone: ctrl.rateLimitEnded),
                  ]),
                ),
                const SizedBox(height: AppSpacing.md),
                InlineNotice.info('Codes are limited to 3 per address every 15 minutes, and 5 per account each hour. Codes already in your inbox still work until they expire.'),
              ] else if (s.mode == VerifyMode.success) ...[
                AppCard(
                  child: Column(children: [
                    Container(width: 64, height: 64, decoration: BoxDecoration(color: colors.successTint, shape: BoxShape.circle), alignment: Alignment.center, child: Icon(Icons.check_rounded, color: colors.success, size: 28)),
                    const SizedBox(height: AppSpacing.md),
                    Text(isChange ? 'Email changed' : 'Email verified', style: type.sectionHeading),
                    const SizedBox(height: AppSpacing.sm),
                    Text(isChange ? 'Your account now uses this address. Other devices were signed out.' : "You're all set — booking, enquiries and messaging are now open to you.", style: type.secondary.copyWith(color: colors.textSecondary), textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.lg),
                    AppButton.primary(label: 'Continue', onPressed: isChange ? () => Navigator.of(context).pop() : goHome),
                  ]),
                ),
              ] else ...[
                OtpCodeEntry(
                  enabled: s.mode != VerifyMode.invalidated && !s.checking,
                  error: s.mode == VerifyMode.wrong || s.mode == VerifyMode.invalidated,
                  clearToken: s.clearToken,
                  onChanged: (c) { setState(() => _code = c); ctrl.codeChanged(); },
                  onCompleted: (_) {},
                ),
                const SizedBox(height: AppSpacing.lg),
                if (s.mode == VerifyMode.wrong) InlineNotice.error("That code isn't right — ${s.attemptsRemaining ?? 0} ${s.attemptsRemaining == 1 ? 'attempt' : 'attempts'} left before it needs a fresh send."),
                if (s.mode == VerifyMode.invalidated) ...[
                  InlineNotice.error('That code has been invalidated after 5 incorrect attempts. Request a fresh one to continue.'),
                  AppButton.destructive(label: 'Send a fresh code', size: AppButtonSize.compact, onPressed: ctrl.resend),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (s.mode == VerifyMode.resent) InlineNotice.success('A new code is on its way to your inbox.'),
                if (s.mode == VerifyMode.sendFailed) InlineNotice.error("We couldn't send a code to this address. Check it's right, or try again in a moment."),
                if (s.mode == VerifyMode.offline) InlineNotice.offline(onRetry: () => _code.length == 6 ? ctrl.verify(_code) : ctrl.resend()),
                AppButton.primary(
                  label: s.checking ? 'Checking…' : 'Verify Email',
                  loading: s.checking,
                  expand: true,
                  onPressed: _code.length == 6 && !s.checking && s.mode != VerifyMode.invalidated ? () => ctrl.verify(_code) : null,
                ),
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: s.resendAvailableAt.isAfter(now)
                      ? CountdownText(until: s.resendAvailableAt, format: (t) => 'Resend code in $t', style: type.secondary.copyWith(color: colors.disabledText))
                      : AppButton.text(label: 'Resend code', size: AppButtonSize.compact, onPressed: ctrl.resend),
                ),
              ],

              if (s.mode != VerifyMode.success && !isChange) ...[
                const SizedBox(height: AppSpacing.xl),
                Text("Booking, enquiring and messaging need a verified email. Browsing doesn't — you can finish this any time.", style: type.caption.copyWith(color: colors.disabledText), textAlign: TextAlign.center),
                Center(child: AppButton.text(label: "I'll do this later", size: AppButtonSize.compact, onPressed: goHome)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}
```

Add `InlineNotice.success(String)` (success tint/border/text) to the notice widget from Task 4. `AppHeader.page` needs a title; pass `'Verify email'` if an empty title looks wrong — the prototype has only a back disc, so a title-less variant of the header is acceptable if `AppHeader` allows it; otherwise use the title.

- [ ] **Step 8: Run** — `flutter test test/features/auth && flutter analyze --no-pub` — Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add frontend/lib/core/clock.dart frontend/lib/features/auth frontend/test/features/auth
git commit -m "Verify Email: six-box entry, resend cooldown and rate-limit wait as separate clocks, every prototype state plus send-failed"
```

---

### Task 7: Session expired, the `AuthGate` root, and the route table

**Files:**
- Create: `frontend/lib/features/auth/presentation/session_expired_screen.dart`, `frontend/lib/features/legal/presentation/legal_placeholder_screen.dart`
- Modify: `frontend/lib/app.dart`, `frontend/test/app_boot_test.dart`
- Test: `frontend/test/features/auth/session_expired_test.dart`, `frontend/test/app_gate_test.dart`

**Reference:** `App States.dc.html` — `Signed out for your security` / `Your session expired while you were away. Sign in again to pick up where you left off.` / `What you were typing is kept — it will be restored after you sign in.` / `Sign In Again`.

**Interfaces:**
- Produces: `SessionExpiredScreen`; `AuthGate` (the `'/'` route: `AuthUnknown` → skeleton, `AuthSessionExpired` → `SessionExpiredScreen`, otherwise the placeholder Home, which for a signed-in user shows an `Account settings` action and for a guest a `Sign in` action); `LegalPlaceholderScreen(title)` for `/legal/terms` and `/legal/privacy` — banner `Placeholder — legal text pending review`, structural headings, no policy prose; the route table with every screen so far plus `/forgot-password` → a small "Coming in Phase 3b" placeholder; `RaajjeProApp` now calls `restore()` once on first build.
- Draft restore: `SignInScreen` on success calls `ref.read(formDraftStoreProvider).peek(...)` is **not** its job; the screen that owns a form saves on `sessionExpired` and restores in `initState`. In this phase the forms that carry drafts are Register (Task 5) and the account forms (Task 9): each saves its controllers into `FormDraftStore` when it receives an `ApiException` with code `SESSION_EXPIRED`, keyed by route name, and restores in `initState`.

- [ ] **Step 1: Failing tests**

`frontend/test/features/auth/session_expired_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/features/auth/presentation/session_expired_screen.dart';

import '../../helpers/pump.dart';

void main() {
  testWidgets('one action, one promise, nothing about lost work', (tester) async {
    await pumpScreen(tester, const SessionExpiredScreen(), routes: {'/sign-in': (_) => const Scaffold(body: Text('SIGNIN'))});
    expect(find.text('Signed out for your security'), findsOneWidget);
    expect(find.textContaining('What you were typing is kept'), findsOneWidget);
    expect(find.textContaining('lost'), findsNothing);
    await tester.tap(find.text('Sign In Again'));
    await settle(tester);
    expect(find.text('SIGNIN'), findsOneWidget);
  });
}
```

`frontend/test/app_gate_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/app.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/core/crash/crash_reporter.dart';

import 'core/auth/auth_controller_test.dart' show tokensJson, userJson;
import 'helpers/fake_api.dart';
import 'helpers/pump.dart';

void main() {
  Future<void> boot(WidgetTester tester, FakeApiClient api, InMemoryTokenStore store) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api), tokenStoreProvider.overrideWithValue(store), crashReporterProvider.overrideWithValue(NoopCrashReporter()), deviceNameProvider.overrideWith((_) async => 'Test')],
      child: const RaajjeProApp(),
    ));
    await settle(tester);
  }

  testWidgets('no tokens → the guest home with a Sign in action; the gallery stays reachable in debug', (tester) async {
    await boot(tester, FakeApiClient(), InMemoryTokenStore());
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Account settings'), findsNothing);
  });

  testWidgets('stored tokens → me → signed-in home with Account settings; a dead session → Session expired', (tester) async {
    final api = FakeApiClient();
    final store = InMemoryTokenStore();
    await store.write(TokenPair.fromJson(tokensJson()));
    api.on('GET', '/v1/auth/me', (_) => userJson(verified: true));
    await boot(tester, api, store);
    expect(find.text('Account settings'), findsOneWidget);

    api.fail('GET', '/v1/auth/me', status: 401, code: 'SESSION_EXPIRED');
    await store.write(TokenPair.fromJson(tokensJson()));
    await boot(tester, api, store);
    expect(find.text('Signed out for your security'), findsOneWidget);
  });

  testWidgets('the legal placeholders are marked as placeholders and carry no policy prose', (tester) async {
    await boot(tester, FakeApiClient(), InMemoryTokenStore());
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pushNamed('/legal/terms');
    await settle(tester);
    expect(find.text('Placeholder — legal text pending review'), findsOneWidget);
    expect(find.textContaining('hereby'), findsNothing);
  });
}
```

- [ ] **Step 2: Run to fail** — Expected: FAIL.

- [ ] **Step 3: `session_expired_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// `App States.dc.html` → Session expired. One action and one promise, which
/// the FormDraftStore keeps true. Nothing here may suggest work was lost.
class SessionExpiredScreen extends StatelessWidget {
  const SessionExpiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: AppSpacing.screenInsets,
          child: AppCard(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 64, height: 64, decoration: BoxDecoration(color: colors.accentTint, shape: BoxShape.circle), alignment: Alignment.center, child: Icon(Icons.lock_outline_rounded, color: colors.primary, size: 28)),
              const SizedBox(height: AppSpacing.lg),
              Text('Signed out for your security', style: type.sectionHeading, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm),
              Text('Your session expired while you were away. Sign in again to pick up where you left off.', style: type.secondary.copyWith(color: colors.textSecondary), textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              Text('What you were typing is kept — it will be restored after you sign in.', style: type.caption.copyWith(color: colors.textTertiary), textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xl),
              AppButton.primary(label: 'Sign In Again', expand: true, onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/sign-in', (_) => false)),
            ]),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: `legal_placeholder_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// Phase 23 owns legal content. Until then these pages exist so the Register
/// links go somewhere honest: a banner and structural headings, and **no
/// policy prose** — root CLAUDE.md 1d forbids invented binding text.
class LegalPlaceholderScreen extends StatelessWidget {
  const LegalPlaceholderScreen({required this.title, super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Scaffold(
      body: Column(children: [
        AppHeader.page(title: title, onBack: () => Navigator.of(context).maybePop()),
        Expanded(
          child: ListView(padding: AppSpacing.screenInsets, children: [
            Container(
              padding: const EdgeInsetsDirectional.all(AppSpacing.md),
              decoration: BoxDecoration(color: colors.warningTint, border: Border.all(color: colors.warningBorder), borderRadius: AppRadius.circular(AppRadius.button)),
              child: Text('Placeholder — legal text pending review', style: type.bodyStrong.copyWith(color: colors.warningText)),
            ),
            const SizedBox(height: AppSpacing.xl),
            for (final h in ['1. Scope', '2. Your account', '3. Bookings and payment', '4. Data and privacy', '5. Contact']) ...[
              Text(h, style: type.sectionHeading),
              const SizedBox(height: AppSpacing.sm),
              Text('[ placeholder — pending legal review ]', style: type.secondary.copyWith(color: colors.disabledText)),
              const SizedBox(height: AppSpacing.lg),
            ],
          ]),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 5: `app.dart`**

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/account/presentation/account_settings_screen.dart';
import 'package:raajjepro/features/auth/presentation/register_screen.dart';
import 'package:raajjepro/features/auth/presentation/session_expired_screen.dart';
import 'package:raajjepro/features/auth/presentation/sign_in_screen.dart';
import 'package:raajjepro/features/auth/presentation/verify_email_screen.dart';
import 'package:raajjepro/features/gallery/presentation/gallery_screen.dart';
import 'package:raajjepro/features/legal/presentation/legal_placeholder_screen.dart';
import 'package:raajjepro/shared/shared.dart';

/// Root widget. Routing is a plain named-route table; the root route is the
/// AuthGate, which switches on the one auth state. Account routes are added
/// by Tasks 8–9 (import `account_settings_screen.dart` once it exists; until
/// then leave that route out).
class RaajjeProApp extends ConsumerStatefulWidget {
  const RaajjeProApp({super.key});
  @override
  ConsumerState<RaajjeProApp> createState() => _RaajjeProAppState();
}

class _RaajjeProAppState extends ConsumerState<RaajjeProApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(authControllerProvider.notifier).restore());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RaajjePro',
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      routes: {
        '/': (_) => const AuthGate(),
        SignInScreen.routeName: (_) => const SignInScreen(),
        RegisterScreen.routeName: (_) => const RegisterScreen(),
        '/forgot-password': (_) => const _ComingSoon(title: 'Forgot password', phase: '3b'),
        '/legal/terms': (_) => const LegalPlaceholderScreen(title: 'Terms of Service'),
        '/legal/privacy': (_) => const LegalPlaceholderScreen(title: 'Privacy Policy'),
        GalleryScreen.routeName: (_) => const GalleryScreen(),
        // Task 8 adds: AccountSettingsScreen.routeName and its sub-screens.
      },
      onGenerateRoute: (settings) {
        if (settings.name == VerifyEmailScreen.routeName) {
          return MaterialPageRoute<void>(builder: (_) => VerifyEmailScreen(args: VerifyEmailArgs.fromRouteArguments(settings.arguments)));
        }
        return null;
      },
    );
  }
}

/// Picks the root screen from the auth state (spec §8). Guests browse freely.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    return switch (state) {
      AuthUnknown() => const Scaffold(body: SkeletonLoader(child: SkeletonRow())),
      AuthSessionExpired() => const SessionExpiredScreen(),
      AuthGuest() => const _PlaceholderHome(user: null),
      AuthSignedIn(:final user) => _PlaceholderHome(user: user),
    };
  }
}

/// Phase 0's boot screen, still the home until Phase 16. Phase 3 adds the
/// two entries it needs — Sign in for a guest, Account settings for a user —
/// the latter a temporary bridge until Phase 6's Profile owns that row.
class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome({required this.user});
  final UserAccount? user;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        const AppHeader.brand(),
        Expanded(
          child: Center(
            child: Padding(
              padding: AppSpacing.screenInsets,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('RaajjePro', style: context.type.screenTitle),
                const SizedBox(height: AppSpacing.xl),
                if (user == null)
                  AppButton.primary(label: 'Sign in', onPressed: () => Navigator.of(context).pushNamed(SignInScreen.routeName))
                else
                  AppButton.secondary(label: 'Account settings', onPressed: () => Navigator.of(context).pushNamed('/account')),
                if (user != null && !user!.emailVerified) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppButton.text(label: 'Verify your email', onPressed: () => Navigator.of(context).pushNamed(VerifyEmailScreen.routeName, arguments: VerifyEmailArgs(email: user!.email, purpose: OtpPurpose.verifyEmail))),
                ],
                if (kDebugMode) ...[
                  const SizedBox(height: AppSpacing.xl),
                  AppButton.text(label: 'Component gallery', onPressed: () => Navigator.of(context).pushNamed(GalleryScreen.routeName)),
                ],
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.title, required this.phase});
  final String title;
  final String phase;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(children: [
      AppHeader.page(title: title, onBack: () => Navigator.of(context).maybePop()),
      Expanded(child: Center(child: Padding(padding: AppSpacing.screenInsets, child: EmptyState(icon: Icons.construction_outlined, title: 'Not built yet', body: 'This flow arrives in Phase $phase.', actionLabel: 'Back', onAction: () => Navigator.of(context).maybePop())))),
    ]),
  );
}
```

Update `test/app_boot_test.dart` to the `boot()` shape from `app_gate_test.dart` and its expectations (guest home shows `Sign in`; the gallery route still works).

- [ ] **Step 6: Run** — `flutter test && flutter analyze --no-pub` — Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add frontend/lib frontend/test
git commit -m "AuthGate root, Session expired screen, legal placeholders and the Phase 3 route table"
```

---

### Task 8: Account Settings, Active sessions, Download my data, Delete account

**Files:**
- Create: `frontend/lib/features/account/controller/account_controller.dart`, `frontend/lib/features/account/presentation/widgets/settings_row.dart`, `frontend/lib/features/account/presentation/account_settings_screen.dart`, `active_sessions_screen.dart`, `download_data_screen.dart`, `delete_account_screen.dart`
- Modify: `frontend/lib/app.dart` (routes `/account`, `/account/sessions`, `/account/download`, `/account/delete`)
- Test: `frontend/test/features/account/account_settings_test.dart`, `active_sessions_test.dart`, `download_data_test.dart`, `delete_account_test.dart`

**Reference:** `Account Settings.dc.html`. Header row: title + `{name} · {email}`. Rows (icon disc, title, subtitle, chevron): `Change password` / `Current password required` · `Change email` / `A code goes to the new address first` · `Change phone` / `Shown as you enter it, like registration` · `Active sessions` / `{n} devices signed in` · `Download my data` / `Profile, bookings, reviews, messages`; then the red `Delete account` / `Accepted immediately, completes within 30 days`. Loading: six skeleton rows. Error: `EmptyState.error` `Couldn't load settings` / `Your connection may have dropped. Nothing is lost — try again.` **Active sessions:** `Everywhere you're signed in. Revoking a device signs out only that device.`; per row device name, `active now` or `Last used N days ago`, `This device` pill with `Sign out`, `Revoke` on others; toast `{device} signed out — only that device`. **Download my data:** `A copy of everything you've put in`, the four items `Profile details · Bookings and their records · Reviews you wrote · Message history`, `Request my data` — per the plan the JSON is fetched and handed to the share sheet; after sharing: `Your export is ready — saved or shared from the sheet you chose.` (the prototype's "emailed within a day" is the flagged divergence). **Delete — confirm:** `Delete your account`, `Your request is accepted immediately — open bookings don't block it. Here's exactly what happens:`, four facts (`Your account freezes at once — no new bookings, no new listings, hidden from search.` · `Deletion completes when your open bookings finish — and within 30 days regardless.` · `Reviews you wrote stay, with your name removed.` · `Identity documents are deleted outright — not anonymised.`), `Type DELETE to confirm`, destructive `Delete my account` enabled only on a match, `Keep my account`. **Delete — frozen:** `Your deletion request is in`, `Your account is frozen as of now — no new bookings, no new listings, and it's hidden from search.`, three facts, `Done`. No rejected state exists.

**Interfaces:**
- Produces: `accountControllerProvider` (`AsyncNotifierProvider<AccountController, UserAccount>` — loads `me`, exposes `reload()`); `sessionsControllerProvider` (`AsyncNotifier<List<SessionInfo>>`, `revoke(id)` returns the device name, `signOutThisDevice()`); `downloadControllerProvider` (`Notifier<DownloadState { fetching, shared, error }>`, `request()` → fetches, writes `raajjepro-export-<date>.json` via `XFile.fromData`, calls `SharePlus.instance.share(ShareParams(files: [...]))` through an injectable `shareProvider` (`Provider<Future<void> Function(XFile)>`) so tests stub it); `deleteControllerProvider` (`Notifier<DeleteState { busy, result: DeletionResult? , offline }>`, `confirm()`); `SettingsRow({icon, title, subtitle, onTap, destructive})`; route names `/account`, `/account/sessions`, `/account/download`, `/account/delete`.
- Relative age helper `relativeAge(DateTime, DateTime now)` → `active now` (< 2 min), `N minutes ago`, `N hours ago`, `N days ago` — in `frontend/lib/core/format/relative_time.dart`.

- [ ] **Step 1: Failing tests** — four files; the shape is the same for each, so `account_settings_test.dart` is given in full and the other three list their cases with the assertions that matter.

`account_settings_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/features/account/presentation/account_settings_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../core/auth/auth_controller_test.dart' show userJson;
import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

void main() {
  late FakeApiClient api;
  setUp(() => api = FakeApiClient());
  Future<void> pump(WidgetTester tester) => pumpScreen(tester, const AccountSettingsScreen(),
      overrides: [apiClientProvider.overrideWithValue(api), tokenStoreProvider.overrideWithValue(InMemoryTokenStore())],
      routes: {for (final r in ['/account/password', '/account/change-email', '/account/phone', '/account/sessions', '/account/download', '/account/delete']) r: (_) => Scaffold(body: Text('ROUTE $r'))});

  testWidgets('loading shows skeleton rows, not a spinner', (tester) async {
    api.gate = Completer<void>();
    api.on('GET', '/v1/auth/me', (_) => userJson());
    api.on('GET', '/v1/auth/sessions', (_) => {'_list': []});
    await pump(tester);
    expect(find.byType(SkeletonLoader), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    api.gate!.complete();
    await settle(tester);
  });

  testWidgets('populated: the six rows, the delete row, the name·email header, no Saved preferences and no toggles', (tester) async {
    api.on('GET', '/v1/auth/me', (_) => userJson(verified: true));
    api.on('GET', '/v1/auth/sessions', (_) => {'_list': [{'id': 'a', 'deviceName': 'iPhone 14', 'createdAt': '2026-09-06T10:00:00.000Z', 'lastSeenAt': '2026-09-06T10:00:00.000Z', 'current': true}, {'id': 'b', 'deviceName': 'Pixel 7', 'createdAt': '2026-09-01T10:00:00.000Z', 'lastSeenAt': '2026-09-03T10:00:00.000Z', 'current': false}]});
    await pump(tester);
    expect(find.text('Aishath Naeema · aishath@example.mv'), findsOneWidget);
    for (final t in ['Change password', 'Change email', 'Change phone', 'Active sessions', 'Download my data', 'Delete account']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('2 devices signed in'), findsOneWidget);
    expect(find.text('Accepted immediately, completes within 30 days'), findsOneWidget);
    expect(find.text('Saved preferences'), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(AppToggle), findsNothing);
    await tester.tap(find.text('Active sessions'));
    await settle(tester);
    expect(find.text('ROUTE /account/sessions'), findsOneWidget);
  });

  testWidgets('error: EmptyState with retry, then populated', (tester) async {
    api.offline('GET', '/v1/auth/me');
    await pump(tester);
    expect(find.text("Couldn't load settings"), findsOneWidget);
    api.on('GET', '/v1/auth/me', (_) => userJson());
    api.on('GET', '/v1/auth/sessions', (_) => {'_list': []});
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.text('Change password'), findsOneWidget);
  });

  testWidgets('frozen: a banner with the deadline and the delete row reads Deletion in progress', (tester) async {
    api.on('GET', '/v1/auth/me', (_) => {...userJson(status: 'frozen'), 'deletionDeadlineAt': '2026-10-06T10:00:00.000Z'});
    api.on('GET', '/v1/auth/sessions', (_) => {'_list': []});
    await pump(tester);
    expect(find.textContaining('Deletion in progress'), findsOneWidget);
    expect(find.textContaining('6 Oct 2026'), findsOneWidget);
  });
}
```

`active_sessions_test.dart` cases: populated shows `This device` + `Sign out` on the current row and `Revoke` on the other with `Last used 3 days ago` (clock overridden to 2026-09-06); tapping `Revoke` opens a confirming `AppBottomSheet`, confirming calls `DELETE /v1/auth/sessions/b`, removes the row and shows the toast `Pixel 7 signed out — only that device`; the current row never shows `Revoke`; loading is a skeleton; error is `EmptyState.error`; the body never contains an IP-looking string (`RegExp(r'\d+\.\d+\.\d+\.\d+')` finds nothing).

`download_data_test.dart` cases: default lists the four items and `Request my data`; tapping shows the button's own loading, calls `GET /v1/users/me/data-export`, passes an `XFile` named `raajjepro-export-2026-09-06.json` whose bytes decode to the returned JSON to the stubbed `shareProvider`, then shows `Your export is ready — saved or shared from the sheet you chose.`; offline shows the inline notice with retry; the screen never says "email" about delivery.

`delete_account_test.dart` cases: confirm shows all four facts and a disabled destructive button; typing `delete` (any case) enables it; `Keep my account` pops; confirming calls `POST /v1/users/me/deletion-request` and shows the frozen card with the three facts and the deadline `6 Oct 2026`; the frozen card has no "can't delete" copy anywhere; a `Done` tap goes home; a second visit for an already-frozen user goes straight to the frozen card (the controller reads `AuthState`).

- [ ] **Step 2: Run to fail** — Expected: FAIL.

- [ ] **Step 3: `relative_time.dart`**

```dart
/// "active now" · "12 minutes ago" · "3 hours ago" · "3 days ago". Sessions
/// use it; nothing else in this phase.
String relativeAge(DateTime when, DateTime now) {
  final d = now.difference(when);
  if (d.inMinutes < 2) return 'active now';
  if (d.inHours < 1) return '${d.inMinutes} minutes ago';
  if (d.inDays < 1) return d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago';
  return d.inDays == 1 ? '1 day ago' : '${d.inDays} days ago';
}

String shortDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
```

- [ ] **Step 4: `account_controller.dart`**

```dart
import 'package:cross_file/cross_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';

final accountControllerProvider = AsyncNotifierProvider<AccountController, UserAccount>(AccountController.new);

/// `me`, fresh, for the settings screens. Applies the result to AuthState so
/// the rest of the app sees a verification or a freeze done here.
class AccountController extends AsyncNotifier<UserAccount> {
  @override
  Future<UserAccount> build() async {
    final user = await ref.read(authApiProvider).me();
    ref.read(authControllerProvider.notifier).applyUser(user);
    return user;
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final sessionsControllerProvider = AsyncNotifierProvider<SessionsController, List<SessionInfo>>(SessionsController.new);

class SessionsController extends AsyncNotifier<List<SessionInfo>> {
  @override
  Future<List<SessionInfo>> build() => ref.read(authApiProvider).sessions();

  /// Revokes one device — only that device (plan §Phase 3). Returns its name for the toast.
  Future<String> revoke(String id) async {
    final current = state.value ?? const [];
    final target = current.firstWhere((s) => s.id == id);
    await ref.read(authApiProvider).revokeSession(id);
    state = AsyncData(current.where((s) => s.id != id).toList());
    return target.deviceName;
  }

  Future<void> signOutThisDevice() => ref.read(authControllerProvider.notifier).signOut();
}

/// Injectable so tests never open a real share sheet.
final shareProvider = Provider<Future<void> Function(XFile file)>((_) => (file) async {
  await SharePlus.instance.share(ShareParams(files: [file], subject: 'Your RaajjePro data export'));
});

class DownloadState {
  const DownloadState({this.fetching = false, this.shared = false, this.offline = false, this.failed = false});
  final bool fetching;
  final bool shared;
  final bool offline;
  final bool failed;
}

final downloadControllerProvider = NotifierProvider<DownloadController, DownloadState>(DownloadController.new);

class DownloadController extends Notifier<DownloadState> {
  @override
  DownloadState build() => const DownloadState();

  /// Synchronous JSON from the API (plan §Phase 3), handed to the OS share
  /// sheet — the prototype's "emailed within a day" is the flagged divergence.
  Future<void> request() async {
    state = const DownloadState(fetching: true);
    try {
      final data = await ref.read(authApiProvider).dataExport();
      final date = ref.read(clockProvider)().toIso8601String().substring(0, 10);
      final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(data));
      await ref.read(shareProvider)(XFile.fromData(bytes, name: 'raajjepro-export-$date.json', mimeType: 'application/json'));
      state = const DownloadState(shared: true);
    } on ApiNetworkException {
      state = const DownloadState(offline: true);
    } on ApiException {
      state = const DownloadState(failed: true);
    }
  }
}

class DeleteState {
  const DeleteState({this.busy = false, this.result, this.offline = false});
  final bool busy;
  final DeletionResult? result;
  final bool offline;
}

final deleteControllerProvider = NotifierProvider<DeleteController, DeleteState>(DeleteController.new);

class DeleteController extends Notifier<DeleteState> {
  @override
  DeleteState build() {
    // Already frozen (a second visit): straight to the frozen card.
    final auth = ref.read(authControllerProvider);
    if (auth is AuthSignedIn && auth.user.status == AccountStatus.frozen && auth.user.deletionDeadlineAt != null) {
      return DeleteState(result: DeletionResult(deletionRequestedAt: auth.user.deletionDeadlineAt!.subtract(const Duration(days: 30)), deletionDeadlineAt: auth.user.deletionDeadlineAt!));
    }
    return const DeleteState();
  }

  /// Queued, never refused (plan §Phase 3). There is no rejected state to render.
  Future<void> confirm() async {
    state = const DeleteState(busy: true);
    try {
      final result = await ref.read(authApiProvider).requestDeletion();
      final auth = ref.read(authControllerProvider);
      if (auth is AuthSignedIn) {
        ref.read(authControllerProvider.notifier).applyUser(auth.user.copyWith(status: AccountStatus.frozen, deletionDeadlineAt: result.deletionDeadlineAt));
      }
      state = DeleteState(result: result);
    } on ApiNetworkException {
      state = const DeleteState(offline: true);
    }
  }
}
```

(`cross_file` comes with `share_plus`; add it to `pubspec.yaml` explicitly as `cross_file: ^0.3.4` if the analyzer complains about a transitive import.)

- [ ] **Step 5: `settings_row.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// One settings row (`Account Settings.dc.html`): a 46 dp icon disc, title,
/// subtitle, chevron, in a card. [destructive] paints the delete row.
class SettingsRow extends StatelessWidget {
  const SettingsRow({required this.icon, required this.title, required this.subtitle, required this.onTap, super.key, this.destructive = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Pressable(
      semanticLabel: '$title, $subtitle',
      onTap: onTap,
      child: AppCard(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.lg, AppSpacing.md, AppSpacing.md, AppSpacing.md),
        child: Row(children: [
          Container(width: 46, height: 46, decoration: BoxDecoration(shape: BoxShape.circle, color: destructive ? colors.errorTint : colors.accentTint), alignment: Alignment.center, child: Icon(icon, color: destructive ? colors.error : colors.primary, size: AppSizes.iconLg)),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: type.cardTitle.copyWith(color: destructive ? colors.errorText : colors.ink)),
            Text(subtitle, style: type.secondary.copyWith(color: colors.textSecondary)),
          ])),
          Icon(Icons.chevron_right_rounded, color: colors.placeholder),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 6: The four screens**

`account_settings_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/format/relative_time.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/account/controller/account_controller.dart';
import 'package:raajjepro/features/account/presentation/widgets/settings_row.dart';
import 'package:raajjepro/shared/shared.dart';

/// Account settings (`Account Settings.dc.html`; plan §Phase 3). Rows the
/// plan names; Saved preferences is deferred past Phase 4 and the notification
/// toggles are Phase 19's, so neither renders here. States: loading (skeleton
/// rows) · error · populated · frozen (banner + changed delete row).
class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});
  static const routeName = '/account';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final user = ref.watch(accountControllerProvider);
    final sessions = ref.watch(sessionsControllerProvider);

    return Scaffold(
      body: Column(children: [
        AppHeader.page(title: 'Account settings', onBack: () => Navigator.of(context).maybePop()),
        Expanded(
          child: user.when(
            loading: () => SkeletonLoader(child: ListView(padding: AppSpacing.screenInsets, children: [for (var i = 0; i < 6; i++) const Padding(padding: EdgeInsetsDirectional.only(bottom: AppSpacing.md), child: SkeletonRow())])),
            error: (_, __) => Center(child: Padding(padding: AppSpacing.screenInsets, child: EmptyState.error(title: "Couldn't load settings", body: 'Your connection may have dropped. Nothing is lost — try again.', onRetry: () => ref.read(accountControllerProvider.notifier).reload()))),
            data: (u) {
              final frozen = u.status == AccountStatus.frozen;
              final count = sessions.value?.length;
              return ListView(padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xxl), children: [
                Text('${u.fullName} · ${u.email}', style: type.secondary.copyWith(color: colors.textSecondary)),
                const SizedBox(height: AppSpacing.md),
                if (frozen && u.deletionDeadlineAt != null) ...[
                  Container(
                    padding: const EdgeInsetsDirectional.all(AppSpacing.md),
                    decoration: BoxDecoration(color: colors.accentTint, border: Border.all(color: colors.accentBorder), borderRadius: AppRadius.circular(AppRadius.button)),
                    child: Text('Deletion in progress — your account is frozen and will be deleted by ${shortDate(u.deletionDeadlineAt!)} at the latest.', style: type.secondary.copyWith(color: colors.accentText)),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                SettingsRow(icon: Icons.lock_outline_rounded, title: 'Change password', subtitle: 'Current password required', onTap: () => Navigator.of(context).pushNamed('/account/password')),
                const SizedBox(height: AppSpacing.md),
                SettingsRow(icon: Icons.mail_outline_rounded, title: 'Change email', subtitle: 'A code goes to the new address first', onTap: () => Navigator.of(context).pushNamed('/account/change-email')),
                const SizedBox(height: AppSpacing.md),
                SettingsRow(icon: Icons.phone_android_outlined, title: 'Change phone', subtitle: 'Shown as you enter it, like registration', onTap: () => Navigator.of(context).pushNamed('/account/phone')),
                const SizedBox(height: AppSpacing.md),
                SettingsRow(icon: Icons.devices_outlined, title: 'Active sessions', subtitle: count == null ? 'Everywhere you\'re signed in' : '$count ${count == 1 ? 'device' : 'devices'} signed in', onTap: () => Navigator.of(context).pushNamed('/account/sessions')),
                const SizedBox(height: AppSpacing.md),
                SettingsRow(icon: Icons.download_outlined, title: 'Download my data', subtitle: 'Profile, bookings, reviews, messages', onTap: () => Navigator.of(context).pushNamed('/account/download')),
                const SizedBox(height: AppSpacing.md),
                SettingsRow(icon: Icons.delete_outline_rounded, title: frozen ? 'Deletion in progress' : 'Delete account', subtitle: frozen ? 'Completes by ${shortDate(u.deletionDeadlineAt!)}' : 'Accepted immediately, completes within 30 days', destructive: true, onTap: () => Navigator.of(context).pushNamed('/account/delete')),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
```

`active_sessions_screen.dart` — a `ConsumerWidget` at `/account/sessions`: header `Active sessions`; the intro line; `sessions.when(loading: skeleton rows, error: EmptyState.error('Couldn\'t load your devices', onRetry: ref.invalidate(sessionsControllerProvider)), data: rows)`. Each row is an `AppCard` with a phone icon disc, the device name, `This device` pill (`AppChip` or a small pill in `successTint`) when `current`, the age via `relativeAge(s.lastSeenAt, ref.watch(clockProvider)())`, and either `AppButton.text('Sign out')` (current → `signOutThisDevice()` then `pushNamedAndRemoveUntil('/')`) or `AppButton.secondary('Revoke', compact)` which opens `showAppBottomSheet` with title `Sign out {name}?`, body `Only that device is signed out. This one stays.`, `AppButton.destructive('Revoke')` → `revoke(id)` → `ScaffoldMessenger.showSnackBar('{name} signed out — only that device')`. Never render an IP or a user agent — the DTO has neither.

`download_data_screen.dart` — `/account/download`: header `Download my data`; an `AppCard` with the download icon disc, `A copy of everything you've put in`, the sentence `Your export includes your profile, bookings, reviews and messages. It comes as a JSON file you can save or share from your phone.`, the four check-marked items, then by state: default `AppButton.primary('Request my data', loading: fetching)`; shared → `InlineNotice.success('Your export is ready — saved or shared from the sheet you chose.')`; offline → `InlineNotice.offline(onRetry)`; failed → `InlineNotice.error("Couldn't prepare your export. Try again in a moment.")`.

`delete_account_screen.dart` — `/account/delete`: header `Delete account`. When `state.result == null`: the confirm card (icon disc in `errorTint`, `Delete your account`, the intro line, the four facts as bullet rows, `Type DELETE to confirm` with an `AppTextField(key: Key('delete-confirm'), hint: 'DELETE', autocorrect: false, textCapitalization: characters)`, `AppButton.destructive('Delete my account', expand, loading: busy, onPressed: typed.trim().toUpperCase() == 'DELETE' && !busy ? confirm : null)`, `AppButton.secondary('Keep my account', onPressed: pop)`; offline → `InlineNotice.offline`). When `result != null`: the frozen card (lock icon disc in `accentTint`, `Your deletion request is in`, the frozen line, three facts, `Deletion completes by ${shortDate(result.deletionDeadlineAt)} at the latest.`, `AppButton.primary('Done', onPressed: pushNamedAndRemoveUntil('/'))`). **No branch anywhere renders a refusal.**

Add the four routes to `app.dart`.

- [ ] **Step 7: Run** — `flutter test test/features/account && flutter analyze --no-pub` — Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add frontend/lib frontend/test frontend/pubspec.yaml frontend/pubspec.lock
git commit -m "Account settings, active sessions with per-device revoke, data export to the share sheet, and the never-refused delete flow"
```

---

### Task 9: Change password, change email, change phone; the phone-never-verified rule test; docs

**Files:**
- Create: `frontend/lib/features/account/controller/change_controllers.dart`, `frontend/lib/features/account/presentation/change_password_screen.dart`, `change_email_screen.dart`, `change_phone_screen.dart`
- Modify: `frontend/lib/app.dart` (routes `/account/password`, `/account/change-email`, `/account/phone`), `frontend/lib/README.md`, `docs/decisions/12-phase-3-identity.md`, `HANDOVER.md`, `README.md`
- Test: `frontend/test/features/account/change_password_test.dart`, `change_email_test.dart`, `change_phone_test.dart`, `frontend/test/features/auth/phone_never_verified_test.dart`

**Interfaces:**
- Produces: `changePasswordControllerProvider` (`Notifier<ChangeFormState { busy, fieldErrors, offline, done }>`, `submit(current, next, confirm)`), `changeEmailControllerProvider` (`submit(newEmail, currentPassword) → VerificationOutcome?` then the screen pushes `VerifyEmailScreen` with `VerifyEmailArgs(email: newEmail, purpose: OtpPurpose.changeEmail, resendOverride: () => api.requestEmailChange(newEmail, currentPassword))`), `changePhoneControllerProvider` (`submit(dialCode, number) → UserAccount?`). Each controller saves its fields to `FormDraftStore` (key = route name) when it catches `SESSION_EXPIRED`, and each screen restores in `initState`.

- [ ] **Step 1: Failing tests** — cases per screen:

`change_password_test.dart`: requirements (`At least 8 characters`) shown **before** submission; mismatch blocks locally with `Passwords don't match` and no request; `INVALID_CREDENTIALS` renders under the current-password field as `Your current password is not right`; success calls `POST /v1/users/me/change-password`, shows a snackbar `Password changed — other devices were signed out` and pops; offline shows the inline notice.

`change_email_test.dart`: `EMAIL_IN_USE` under the field; `EMAIL_UNCHANGED` under the field as `That is already your email address`; `INVALID_CREDENTIALS` under the password field; success calls `POST /v1/users/me/change-email/request` with `{newEmail, currentPassword}` and navigates to `VerifyEmailScreen` showing the **new** address and `Verify your new email`; on that screen `POST /v1/users/me/change-email/confirm` success shows `Email changed`; a draft saved under `/account/change-email` is restored into the field on `initState`.

`change_phone_test.dart`: the current number shown as plain text `Current number: +960 7771234` with no check icon and no "verified"; the same `PhoneField` as Register; `PHONE_IN_USE` renders the verified-provider copy under the field; `VALIDATION_FAILED` for `phone` renders as errorText; success `PATCH /v1/users/me/phone` shows `Number updated — shown as you entered it` and the new number, again with no check icon; the whole tree after success contains no `Icons.check_circle`, `Icons.verified`, or the word `verified` within 40 characters of the number.

`phone_never_verified_test.dart` — the design-rule test, over every screen in `features/auth` and `features/account` that can show a phone (Register after `PHONE_IN_USE`, Change phone before and after success, Account settings populated): pump each, collect every `Text` widget's data and every `Icon`'s `icon`, and assert (a) no `Icon` among `[Icons.check_circle, Icons.check_circle_outline, Icons.verified, Icons.verified_user]` is rendered within the same `Row` as a `Text` matching `RegExp(r'\+\d')`, and (b) no `Text` containing `RegExp(r'\+\d[\d ]{5,}')` also contains `verified` (case-insensitive). Both assertions must fail if someone adds a tick next to a number.

- [ ] **Step 2: Run to fail** — Expected: FAIL.

- [ ] **Step 3: `change_controllers.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/form_draft_store.dart';

class ChangeFormState {
  const ChangeFormState({this.busy = false, this.fieldErrors = const {}, this.offline = false, this.done = false});
  final bool busy;
  final Map<String, String> fieldErrors;
  final bool offline;
  final bool done;
  ChangeFormState copyWith({bool? busy, Map<String, String>? fieldErrors, bool? offline, bool? done}) =>
      ChangeFormState(busy: busy ?? this.busy, fieldErrors: fieldErrors ?? this.fieldErrors, offline: offline ?? this.offline, done: done ?? this.done);
}

/// Shared error mapping for the three change forms. A dead session saves the
/// draft so the Session Expired promise holds.
abstract class ChangeFormController extends Notifier<ChangeFormState> {
  @override
  ChangeFormState build() => const ChangeFormState();

  String get draftKey;

  Future<T?> run<T>(Future<T> Function() action, {required Map<String, String> draft, Map<String, String> Function(ApiException e)? mapError}) async {
    state = state.copyWith(busy: true, fieldErrors: const {}, offline: false);
    try {
      final result = await action();
      state = state.copyWith(busy: false, done: true);
      return result;
    } on ApiException catch (e) {
      if (e.code == 'SESSION_EXPIRED') ref.read(formDraftStoreProvider).save(draftKey, draft);
      final errors = <String, String>{for (final f in e.fieldErrors) f.path.split('.').first: f.message};
      state = state.copyWith(busy: false, fieldErrors: errors.isEmpty ? (mapError?.call(e) ?? {'form': e.message}) : errors);
    } on ApiNetworkException {
      state = state.copyWith(busy: false, offline: true);
    }
    return null;
  }

  void local(Map<String, String> errors) => state = state.copyWith(fieldErrors: errors);
  void clear(String path) => state = state.copyWith(fieldErrors: Map.of(state.fieldErrors)..remove(path));
}

final changePasswordControllerProvider = NotifierProvider<ChangePasswordController, ChangeFormState>(ChangePasswordController.new);

class ChangePasswordController extends ChangeFormController {
  @override
  String get draftKey => '/account/password';

  Future<bool> submit(String current, String next, String confirm) async {
    if (next != confirm) { local({'confirmPassword': "Passwords don't match"}); return false; }
    if (next.length < 8) { local({'newPassword': 'At least 8 characters'}); return false; }
    final ok = await run(() => ref.read(authApiProvider).changePassword(current, next), draft: const {}, mapError: (e) => e.code == 'INVALID_CREDENTIALS' ? {'currentPassword': 'Your current password is not right'} : {'form': e.message});
    return ok != null || state.done;
  }
}

final changeEmailControllerProvider = NotifierProvider<ChangeEmailController, ChangeFormState>(ChangeEmailController.new);

class ChangeEmailController extends ChangeFormController {
  @override
  String get draftKey => '/account/change-email';

  Future<VerificationOutcome?> submit(String newEmail, String currentPassword) => run(
    () => ref.read(authApiProvider).requestEmailChange(newEmail.trim(), currentPassword),
    draft: {'newEmail': newEmail},
    mapError: (e) => switch (e.code) {
      'EMAIL_IN_USE' => {'newEmail': 'This email already has a RaajjePro account.'},
      'EMAIL_UNCHANGED' => {'newEmail': 'That is already your email address'},
      'INVALID_CREDENTIALS' => {'currentPassword': 'Your current password is not right'},
      'OTP_RATE_LIMITED' => {'form': 'Too many codes requested — wait ${e.retryAfterSeconds ?? 60} seconds and try again'},
      _ => {'form': e.message},
    },
  );
}

final changePhoneControllerProvider = NotifierProvider<ChangePhoneController, ChangeFormState>(ChangePhoneController.new);

class ChangePhoneController extends ChangeFormController {
  @override
  String get draftKey => '/account/phone';

  Future<UserAccount?> submit(String dialCode, String number) async {
    final user = await run(
      () => ref.read(authApiProvider).changePhone(dialCode.trim(), number.trim()),
      draft: {'dialCode': dialCode, 'number': number},
      mapError: (e) => e.code == 'PHONE_IN_USE' ? {'phone': 'This number belongs to a verified provider account.'} : {'form': e.message},
    );
    if (user != null) ref.read(authControllerProvider.notifier).applyUser(user);
    return user;
  }
}
```

- [ ] **Step 4: The three screens**

`change_password_screen.dart` — `ConsumerStatefulWidget` at `/account/password`: header `Change password`; three `AppTextField`s (`Current password`, `New password` with helper `At least 8 characters`, `Confirm new password`), each obscured with a reveal `Pressable`; field errors from `state.fieldErrors[...]`; `InlineNotice.offline`/`.error(form)`; `AppButton.primary('Change password', loading: busy)`; on `true` → `ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed — other devices were signed out')))` then `Navigator.pop`. Below the form a caption: `Changing your password signs out every other device.`

`change_email_screen.dart` — `/account/change-email`: header `Change email`; a caption `We'll send a 6-digit code to the new address. Nothing changes until you enter it.`; `AppTextField('New email address', key: Key('ce-email'))` restored from `formDraftStoreProvider.take('/account/change-email')?['newEmail']` in `initState`; `AppTextField('Current password', obscure)`; errors under their fields; `AppButton.primary('Send code', loading: busy)`; on an outcome → `Navigator.pushReplacementNamed(VerifyEmailScreen.routeName, arguments: VerifyEmailArgs(email: newEmail, purpose: OtpPurpose.changeEmail, initialStatus: outcome.status, resendAvailableAt: outcome.resendAvailableAt, resendOverride: () => ref.read(authApiProvider).requestEmailChange(newEmail, currentPassword)))`.

`change_phone_screen.dart` — `/account/phone`: header `Change phone`; `Text('Current number: ${user.phone?.display ?? 'none on file'}')` as plain body text — no icon; a caption `Shown as you enter it, like registration. Nothing here checks the number belongs to you.`; the Task 5 `PhoneField` prefilled with the current dial code and number (or `+960` and empty), with the same `PHONE_IN_USE` rich error; `AppButton.primary('Save number', loading: busy)`; on success the current-number line updates and `InlineNotice.success('Number updated — shown as you entered it')` appears. **No success icon of any kind.**

Add the three routes to `app.dart`.

- [ ] **Step 5: Run everything** — `cd frontend && flutter test && flutter analyze --no-pub` — Expected: PASS. Then run the app against the dev server (`flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000` on an Android emulator or `http://localhost:3000` on desktop/iOS simulator) and walk register → Verify Email (read the code from `backend/.mail/`) → home → Account settings → each sub-screen; record what was seen in the decision record.

- [ ] **Step 6: Documents**

- `frontend/lib/README.md`: add rows for `core/api`, `core/auth`, `core/crash`, `core/clock.dart`, `core/format`, `features/auth`, `features/account`, `features/legal` (placeholder pages, Phase 23 replaces).
- `docs/decisions/12-phase-3-identity.md`: fill the frontend rows of the Done-when table ("Frontend: Login, Register (pixel-match), OTP verification screen, account settings sub-screens" → the screens and their state tests), the two prototype divergences, and the dev-server walkthrough.
- `HANDOVER.md` and `README.md`: Phase 3 built (both halves); `flutter run --dart-define=API_BASE_URL=…`; the code is in `backend/.mail/`; next `/phase-3b`.

- [ ] **Step 7: `scripts/verify.sh`, commit, push**

```bash
scripts/verify.sh
git add -A frontend docs README.md HANDOVER.md
git commit -m "Change password, email and phone screens; the phone-never-verified rule test; Phase 3 frontend documented"
git fetch origin && git rebase origin/main && git push origin main
```

---

## Self-review against the spec (§8)

- **`core/api`** — Task 1: base URL, bearer, envelope, single-flight refresh and retry, `SESSION_EXPIRED` hand-off, `ApiNetworkException`.
- **`core/auth`** — Task 2: secure token store, `AuthController` states `unknown → guest | signedIn | sessionExpired`, restore with background `me`, `FormDraftStore`; draft save/restore wired in Tasks 5 (Register) and 9 (account forms); Session Expired copy in Task 7.
- **`core/crash`** — Task 3: interface, Sentry impl active only with a DSN, `runZonedGuarded`, `FlutterError.onError`, user id only.
- **Sign In** — Task 4, every listed state. **Register** — Task 5, every listed state, `EMAIL_IN_USE` and `PHONE_IN_USE` renderings, disclaimer, terms placeholders. **Verify Email** — Task 6, all eight modes, two clocks, `Not your address? Change it`, `I'll do this later`. **Session expired** — Task 7. **Account Settings / Active sessions / Download / Delete** — Task 8 with the frozen state and no rejected state. **Change password / email / phone** — Task 9, with change-email reusing the Verify Email screen for purpose `changeEmail`.
- **Routing** — Task 7: named routes, `AuthGate`, guests unchallenged, the temporary Account settings entry on the placeholder Home, legal placeholders with no policy prose.
- **Tests listed in the spec** — every screen's states (Tasks 4–9), `AuthController` refresh/retry/single-flight/session-expired/draft (Tasks 1–2), Register field mapping (Task 5), Verify Email timers by fake clock (Task 6), the phone-never-verified design-rule test (Task 9).
- **Deferred by decision** — Saved preferences row and the marketing/digest toggles are asserted absent (Task 8).
- **Placeholders** — none. **Type consistency** — `VerifyEmailArgs`/`OtpPurpose` are defined once in `verify_email_controller.dart` and re-exported by the screen; `InlineNotice` (Task 4) is the one notice widget; `PhoneField` (Task 5) is reused by Change phone; `userJson`/`tokensJson` fixtures come from `auth_controller_test.dart` everywhere.
