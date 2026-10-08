import 'dart:convert';
import 'dart:math';

import 'package:awesome_dart_auth/awesome_dart_auth.dart';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// In-memory test stores
// ---------------------------------------------------------------------------

class _UserStore implements AdminUserStore {
  final Map<String, AuthUser> _users = {};

  @override
  Future<AuthUser?> findByEmail(String email) async =>
      _users.values.where((u) => u.email == email).firstOrNull;

  @override
  Future<AuthUser?> findById(String id) async => _users[id];

  @override
  Future<AuthUser> save(AuthUser user) async {
    _users[user.id] = user;
    return user;
  }

  @override
  Future<AuthUser> update(AuthUser user) async {
    _users[user.id] = user;
    return user;
  }

  @override
  Future<void> delete(String id) async => _users.remove(id);

  @override
  Future<UserListResult> listUsers({
    int limit = 20,
    int offset = 0,
    String? filter,
  }) async {
    final needle = filter?.toLowerCase();
    final all = _users.values
        .where(
          (u) =>
              needle == null ||
              u.email.toLowerCase().contains(needle) ||
              u.id.toLowerCase().contains(needle),
        )
        .toList(growable: false);
    final start = offset.clamp(0, all.length);
    final end = min(start + limit, all.length);
    return (users: all.sublist(start, end), total: all.length);
  }
}

class _SessionStore implements AdminSessionStore {
  final Map<String, AuthSession> sessions = <String, AuthSession>{};
  final Map<String, String> _idByHandle = <String, String>{};

  @override
  Future<AuthSession?> findById(String id) async => sessions[id];

  @override
  Future<void> revoke(String id) async {
    final session = sessions[id];
    if (session != null) {
      sessions[id] = session.copyWith(revoked: true);
    }
  }

  @override
  Future<void> save(AuthSession session) async {
    sessions[session.id] = session;
    if (session.handle case final handle?) {
      _idByHandle[handle] = session.id;
    }
  }

  @override
  Future<SessionListResult> listAllSessions({
    int limit = 20,
    int offset = 0,
    String? filter,
  }) async {
    final needle = filter?.toLowerCase();
    final all = sessions.values
        .where(
          (s) =>
              needle == null ||
              s.userId.toLowerCase().contains(needle) ||
              (s.handle?.toLowerCase().contains(needle) ?? false) ||
              (s.userAgent?.toLowerCase().contains(needle) ?? false),
        )
        .toList(growable: false);
    final start = offset.clamp(0, all.length);
    final end = min(start + limit, all.length);
    return (sessions: all.sublist(start, end), total: all.length);
  }

  @override
  Future<void> revokeByHandle(String handle) async {
    final targetId = _idByHandle[handle];
    final target = targetId == null ? null : sessions[targetId];
    if (target == null) return;
    sessions[target.id] = target.copyWith(revoked: true);
  }
}

class _TokenStore implements TokenStore {
  final Map<String, TokenRecord> _tokens = <String, TokenRecord>{};

  @override
  Future<void> consume(String token) async {
    final current = _tokens[token];
    if (current == null) return;
    _tokens[token] = current.copyWith(consumedAt: DateTime.now().toUtc());
  }

  @override
  Future<TokenRecord?> findByToken(String token) async => _tokens[token];

  @override
  Future<void> save(TokenRecord record) async {
    _tokens[record.token] = record;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Map<String, dynamic> _jsonBody(String body) =>
    jsonDecode(body) as Map<String, dynamic>;

Future<Response> _get(AuthRouter router, String path) async =>
    router.handler(Request('GET', Uri.parse('http://localhost$path')));

Future<String> _sha256Of(Response response) async => sha256
    .convert(await response.read().expand((chunk) => chunk).toList())
    .toString();

/// awesome-node-auth 1.10.8 `src/ui/assets/auth.js`, the bytes every port
/// serves.
const _referenceAuthJsLength = 31277;
const _referenceAuthJsSha256 =
    'ccc707ae777d5625150dca819bd7d1d15ade0db439e7329011d312e231d6698f';

/// What awesome-node-auth 1.10.8 answers at `GET /auth/ui/config` with
/// `ui.enabled` and nothing else configured.
final String _referenceDefaultUiConfig = [
  '{"apiPrefix":"/auth","features":{"register":false,"magicLink":false,',
  '"sms":false,"google":false,"github":false,"forgotPassword":false,',
  '"verifyEmail":false,"twoFactor":false},"ui":{"primaryColor":"#4a90d9",',
  '"secondaryColor":"#6c757d","siteName":"Awesome Node Auth"},',
  '"translations":{},"lang":"en","headless":false}',
].join();

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AuthRouter', () {
    late AuthConfig config;
    late _UserStore userStore;
    late _SessionStore sessionStore;
    late _TokenStore tokenStore;
    late AuthService service;
    late AuthRouter router;

    setUp(() {
      config = AuthConfig.development(jwtSecret: 'secret1234');
      userStore = _UserStore();
      sessionStore = _SessionStore();
      tokenStore = _TokenStore();
      service = AuthService(
        config: config,
        userStore: userStore,
        sessionStore: sessionStore,
      );
      router = AuthRouter(
        config: config,
        authService: service,
        tokenStore: tokenStore,
      );
    });

    test('redirects /auth/ui to upstream login page', () async {
      final response = await router.handler(
        Request('GET', Uri.parse('http://localhost/auth/ui')),
      );
      expect(response.statusCode, 302);
      expect(response.headers['location'], '/auth/ui/login');
    });

    test('serves upstream login UI + base.css + auth.js assets', () async {
      final loginResponse = await router.handler(
        Request('GET', Uri.parse('http://localhost/auth/ui/login')),
      );
      final cssResponse = await router.handler(
        Request('GET', Uri.parse('http://localhost/auth/ui/base.css')),
      );
      final jsResponse = await router.handler(
        Request('GET', Uri.parse('http://localhost/auth/ui/auth.js')),
      );

      final loginBody = await loginResponse.readAsString();
      final cssBody = await cssResponse.readAsString();
      final jsBody = await jsResponse.readAsString();

      expect(loginResponse.statusCode, 200);
      expect(loginBody, contains('Login - Awesome Node Auth'));
      expect(cssResponse.statusCode, 200);
      expect(cssBody, contains('--primary-color'));
      expect(jsResponse.statusCode, 200);
      expect(jsBody, contains('window.AwesomeNodeAuth'));
    });

    test('issues a token pair from POST /auth/token', () async {
      final response = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/token'),
          body: jsonEncode(const {
            'userId': 'user-1',
            'email': 'user@example.com',
          }),
          headers: const {'content-type': 'application/json'},
        ),
      );
      final body = _jsonBody(await response.readAsString());

      expect(response.statusCode, 200);
      expect(body['accessToken'], isA<String>());
      expect(body['refreshToken'], isA<String>());
      expect(body['tokenType'], 'Bearer');
    });

    test('registers a new user via POST /auth/register', () async {
      final response = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/register'),
          body: jsonEncode({
            'email': 'alice@example.com',
            'password': 'SecurePass1!',
          }),
          headers: const {'content-type': 'application/json'},
        ),
      );
      final body = _jsonBody(await response.readAsString());

      expect(response.statusCode, 200);
      expect(body['accessToken'], isA<String>());
      expect((body['user'] as Map<String, dynamic>)['email'], 'alice@example.com');
    });

    test('returns 400 when registering duplicate email', () async {
      const payload = {'email': 'bob@example.com', 'password': 'Password123'};
      await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/register'),
          body: jsonEncode(payload),
          headers: const {'content-type': 'application/json'},
        ),
      );
      final response = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/register'),
          body: jsonEncode(payload),
          headers: const {'content-type': 'application/json'},
        ),
      );
      expect(response.statusCode, 400);
    });

    test('logs in and returns tokens via POST /auth/login', () async {
      await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/register'),
          body: jsonEncode({
            'email': 'carol@example.com',
            'password': 'MySecret99!',
          }),
          headers: const {'content-type': 'application/json'},
        ),
      );

      final response = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/login'),
          body: jsonEncode({
            'email': 'carol@example.com',
            'password': 'MySecret99!',
          }),
          headers: const {'content-type': 'application/json'},
        ),
      );
      final body = _jsonBody(await response.readAsString());

      expect(response.statusCode, 200);
      expect(body['accessToken'], isA<String>());
    });

    test('returns 401 for wrong password via POST /auth/login', () async {
      await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/register'),
          body: jsonEncode({
            'email': 'dave@example.com',
            'password': 'CorrectPw1!',
          }),
          headers: const {'content-type': 'application/json'},
        ),
      );

      final response = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/login'),
          body: jsonEncode({
            'email': 'dave@example.com',
            'password': 'WrongPw!',
          }),
          headers: const {'content-type': 'application/json'},
        ),
      );
      expect(response.statusCode, 401);
    });

    test('refreshes tokens via POST /auth/refresh', () async {
      final regResponse = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/register'),
          body: jsonEncode({
            'email': 'eve@example.com',
            'password': 'StrongPw1!',
          }),
          headers: const {'content-type': 'application/json'},
        ),
      );
      final regBody = _jsonBody(await regResponse.readAsString());
      final refreshToken = regBody['refreshToken'] as String;

      final response = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/refresh'),
          body: jsonEncode({'refreshToken': refreshToken}),
          headers: const {'content-type': 'application/json'},
        ),
      );
      final body = _jsonBody(await response.readAsString());

      expect(response.statusCode, 200);
      expect(body['accessToken'], isA<String>());
    });

    test('returns 401 from GET /auth/me when unauthenticated', () async {
      final response = await router.handler(
        Request('GET', Uri.parse('http://localhost/auth/me')),
      );
      expect(response.statusCode, 401);
    });

    test('returns user from GET /auth/me with valid token', () async {
      final regResponse = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/register'),
          body: jsonEncode({
            'email': 'frank@example.com',
            'password': 'SecretPw1!',
          }),
          headers: const {'content-type': 'application/json'},
        ),
      );
      final regBody = _jsonBody(await regResponse.readAsString());
      final accessToken = regBody['accessToken'] as String;

      final meResponse = await router.handler(
        Request(
          'GET',
          Uri.parse('http://localhost/auth/me'),
          headers: {'authorization': 'Bearer $accessToken'},
        ),
      );
      final meBody = _jsonBody(await meResponse.readAsString());

      expect(meResponse.statusCode, 200);
      expect(meBody['email'], 'frank@example.com');
    });

    test('logouts via POST /auth/logout', () async {
      final regResponse = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/register'),
          body: jsonEncode({
            'email': 'grace@example.com',
            'password': 'Password99!',
          }),
          headers: const {'content-type': 'application/json'},
        ),
      );
      final regBody = _jsonBody(await regResponse.readAsString());
      final accessToken = regBody['accessToken'] as String;

      final response = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/logout'),
          headers: {'authorization': 'Bearer $accessToken'},
        ),
      );
      final body = _jsonBody(await response.readAsString());

      expect(response.statusCode, 200);
      expect(body['ok'], true);
    });

    test('TOTP setup returns secret + otpAuthUrl', () async {
      final regResponse = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/register'),
          body: jsonEncode({
            'email': 'henry@example.com',
            'password': 'SafePw123!',
          }),
          headers: const {'content-type': 'application/json'},
        ),
      );
      final regBody = _jsonBody(await regResponse.readAsString());
      final accessToken = regBody['accessToken'] as String;

      final setupResponse = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/2fa/setup'),
          headers: {'authorization': 'Bearer $accessToken'},
        ),
      );
      final setupBody = _jsonBody(await setupResponse.readAsString());

      expect(setupResponse.statusCode, 200);
      expect(setupBody['secret'], isA<String>());
      expect(setupBody['otpAuthUrl'], contains('otpauth://totp/'));
    });

    test('serves UI config from GET /auth/ui/config', () async {
      final customConfig = config.copyWith(
        uiConfig: {'theme': 'dark', 'brand': 'ACME'},
      );
      final customRouter = AuthRouter(
        config: customConfig,
        authService: service,
      );

      final response = await customRouter.handler(
        Request('GET', Uri.parse('http://localhost/auth/ui/config')),
      );
      final body = _jsonBody(await response.readAsString());

      expect(response.statusCode, 200);
      expect(body['theme'], 'dark');
    });

    group('auth.js and /ui/config', () {
      test('auth.js is byte-identical to awesome-node-auth 1.10.8', () async {
        final response = await _get(router, '/auth/ui/auth.js');
        final bytes = await response.read().expand((chunk) => chunk).toList();

        expect(response.statusCode, 200);
        expect(
          response.headers['content-type'],
          'application/javascript; charset=utf-8',
        );
        expect(bytes, hasLength(_referenceAuthJsLength));
        expect(sha256.convert(bytes).toString(), _referenceAuthJsSha256);
      });

      test('default /auth/ui/config is what node serves by default', () async {
        final response = await _get(router, '/auth/ui/config');

        expect(response.statusCode, 200);
        expect(
          response.headers['content-type'],
          'application/json; charset=utf-8',
        );
        expect(await response.readAsString(), _referenceDefaultUiConfig);
      });

      test('apiBasePath alone moves auth.js, the pages and /ui/config', () async {
        final moved = AuthRouter(
          config: config.copyWith(apiBasePath: '/api/auth'),
          authService: service,
        );

        final js = await _get(moved, '/api/auth/ui/auth.js');
        expect(js.statusCode, 200);
        expect(await js.readAsString(), embeddedAuthJs);

        final ui = await _get(moved, '/api/auth/ui');
        expect(ui.statusCode, 302);
        expect(ui.headers['location'], '/api/auth/ui/login');
        expect((await _get(moved, '/api/auth/ui/login')).statusCode, 200);
        expect((await _get(moved, '/api/auth/ui/base.css')).statusCode, 200);

        final uiConfig = await _get(moved, '/api/auth/ui/config');
        expect(uiConfig.statusCode, 200);
        expect(
          _jsonBody(await uiConfig.readAsString())['apiPrefix'],
          '/api/auth',
        );

        for (final old in const [
          '/auth/ui',
          '/auth/ui/auth.js',
          '/auth/ui/login',
          '/auth/ui/base.css',
          '/auth/ui/config',
        ]) {
          expect((await _get(moved, old)).statusCode, 404, reason: old);
        }
      });

      test('explicit authUiPath and authJsPath still win', () async {
        final custom = AuthRouter(
          config: config.copyWith(
            authUiPath: '/login-ui',
            authJsPath: '/static/auth.js',
          ),
          authService: service,
        );

        expect((await _get(custom, '/static/auth.js')).statusCode, 200);
        expect((await _get(custom, '/login-ui/login')).statusCode, 200);
        expect((await _get(custom, '/auth/ui/auth.js')).statusCode, 404);
        expect((await _get(custom, '/auth/ui/login')).statusCode, 404);
        expect((await _get(custom, '/auth/ui/config')).statusCode, 200);
      });

      test('moving only authUiPath keeps auth.js at /auth/ui', () async {
        final pagesMoved = AuthRouter(
          config: config.copyWith(authUiPath: '/login-ui'),
          authService: service,
        );

        final js = await _get(pagesMoved, '/auth/ui/auth.js');
        expect(js.statusCode, 200);
        expect(await _sha256Of(js), _referenceAuthJsSha256);
        expect((await _get(pagesMoved, '/auth/ui/config')).statusCode, 200);
        expect((await _get(pagesMoved, '/login-ui/login')).statusCode, 200);
        expect((await _get(pagesMoved, '/auth/ui/login')).statusCode, 404);
      });

      test('enableAuthUi false is headless: auth.js 200, pages 404', () async {
        final headless = AuthRouter(
          config: config.copyWith(enableAuthUi: false),
          authService: service,
        );

        expect((await _get(headless, '/auth/ui/auth.js')).statusCode, 200);
        expect((await _get(headless, '/auth/ui')).statusCode, 404);
        expect((await _get(headless, '/auth/ui/login')).statusCode, 404);
        expect((await _get(headless, '/auth/ui/base.css')).statusCode, 404);

        final uiConfig = await _get(headless, '/auth/ui/config');
        expect(uiConfig.statusCode, 200);
        final body = _jsonBody(await uiConfig.readAsString());
        expect(body['headless'], isTrue);
        expect(body['apiPrefix'], '/auth');
      });

      test('uiConfig is merged into the document', () async {
        final branded = AuthRouter(
          config: config.copyWith(
            uiConfig: {
              'ui': {'siteName': 'ACME'},
              'features': {'register': true},
              'theme': 'dark',
            },
          ),
          authService: service,
        );

        final body = _jsonBody(
          await (await _get(branded, '/auth/ui/config')).readAsString(),
        );
        final ui = body['ui'] as Map<String, dynamic>;
        final features = body['features'] as Map<String, dynamic>;

        expect(body['apiPrefix'], '/auth');
        expect(body['theme'], 'dark');
        expect(ui['siteName'], 'ACME');
        expect(ui['primaryColor'], '#4a90d9');
        expect(features['register'], isTrue);
        expect(features['google'], isFalse);
        expect(features, hasLength(8));
      });

      test('lang follows ?lang= and falls back to defaultLocale', () async {
        final it = _jsonBody(
          await (await _get(router, '/auth/ui/config?lang=it')).readAsString(),
        );
        final empty = _jsonBody(
          await (await _get(router, '/auth/ui/config?lang=')).readAsString(),
        );

        expect(it['lang'], 'it');
        expect(empty['lang'], 'en');
      });

      test('google and github follow the OAuth wiring', () async {
        final oauth = AuthRouter(
          config: config.copyWith(oauthProviders: const {'google'}),
          authService: service,
          callbacks: AuthCallbacks(
            onOAuthStart: (provider, redirectUri) async =>
                'https://idp.example.com/$provider',
          ),
        );

        final body = _jsonBody(
          await (await _get(oauth, '/auth/ui/config')).readAsString(),
        );
        final features = body['features'] as Map<String, dynamic>;

        expect(features['google'], isTrue);
        expect(features['github'], isFalse);
      });
    });

    test('serves upstream admin UI assets', () async {
      final adminResponse = await router.handler(
        Request('GET', Uri.parse('http://localhost/auth/admin')),
      );
      final adminJsResponse = await router.handler(
        Request('GET', Uri.parse('http://localhost/auth/admin/assets/admin.js')),
      );
      final adminCssResponse = await router.handler(
        Request('GET', Uri.parse('http://localhost/auth/admin/assets/admin.css')),
      );

      final adminBody = await adminResponse.readAsString();
      final adminJsBody = await adminJsResponse.readAsString();
      final adminCssBody = await adminCssResponse.readAsString();

      expect(adminResponse.statusCode, 200);
      expect(adminBody, contains('awesome-node-auth Admin'));
      expect(adminJsResponse.statusCode, 200);
      expect(adminJsBody, contains('function buildNav()'));
      expect(adminCssResponse.statusCode, 200);
      expect(adminCssBody, contains('.login-card'));
      expect(adminBody, contains('"featRoles":true'));
    });

    test('admin API returns users when authenticated', () async {
      final registerResponse = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/register'),
          body: jsonEncode({
            'email': 'admin-users@example.com',
            'password': 'StrongPass1!',
          }),
          headers: const {'content-type': 'application/json'},
        ),
      );
      final registerBody = _jsonBody(await registerResponse.readAsString());
      final accessToken = registerBody['accessToken'] as String;

      final response = await router.handler(
        Request(
          'GET',
          Uri.parse('http://localhost/auth/admin/api/users?limit=20&offset=0'),
          headers: {'authorization': 'Bearer $accessToken'},
        ),
      );
      final body = _jsonBody(await response.readAsString());

      expect(response.statusCode, 200);
      expect(body['users'], isA<List<dynamic>>());
      expect(body['total'], greaterThanOrEqualTo(1));
    });

    test('admin API lists and revokes sessions', () async {
      final registerResponse = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/register'),
          body: jsonEncode({
            'email': 'admin-sessions@example.com',
            'password': 'StrongPass1!',
          }),
          headers: const {'content-type': 'application/json'},
        ),
      );
      final registerBody = _jsonBody(await registerResponse.readAsString());
      final accessToken = registerBody['accessToken'] as String;

      final listResponse = await router.handler(
        Request(
          'GET',
          Uri.parse('http://localhost/auth/admin/api/sessions?limit=20&offset=0'),
          headers: {'authorization': 'Bearer $accessToken'},
        ),
      );
      final listBody = _jsonBody(await listResponse.readAsString());
      expect(listResponse.statusCode, 200);
      expect(listBody['sessions'], isA<List<dynamic>>());

      final sessions = (listBody['sessions'] as List<dynamic>);
      if (sessions.isNotEmpty) {
        final handle =
            (sessions.first as Map<String, dynamic>)['sessionHandle'] as String;
        final revokeResponse = await router.handler(
          Request(
            'DELETE',
            Uri.parse('http://localhost/auth/admin/api/sessions/$handle'),
            headers: {'authorization': 'Bearer $accessToken'},
          ),
        );
        expect(revokeResponse.statusCode, 200);
      }
    });

    test('admin API supports settings and templates', () async {
      final registerResponse = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/register'),
          body: jsonEncode({
            'email': 'admin-settings@example.com',
            'password': 'StrongPass1!',
          }),
          headers: const {'content-type': 'application/json'},
        ),
      );
      final registerBody = _jsonBody(await registerResponse.readAsString());
      final accessToken = registerBody['accessToken'] as String;

      final putSettings = await router.handler(
        Request(
          'PUT',
          Uri.parse('http://localhost/auth/admin/api/settings'),
          headers: {
            'authorization': 'Bearer $accessToken',
            'content-type': 'application/json',
          },
          body: jsonEncode({'requireEmailVerification': true}),
        ),
      );
      expect(putSettings.statusCode, 200);

      final getSettings = await router.handler(
        Request(
          'GET',
          Uri.parse('http://localhost/auth/admin/api/settings'),
          headers: {'authorization': 'Bearer $accessToken'},
        ),
      );
      final settingsBody = _jsonBody(await getSettings.readAsString());
      expect(getSettings.statusCode, 200);
      expect(settingsBody['requireEmailVerification'], true);

      final saveTemplate = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/admin/api/templates/mail'),
          headers: {
            'authorization': 'Bearer $accessToken',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'id': 'welcome',
            'baseHtml': '<h1>Hello</h1>',
            'baseText': 'Hello',
            'translations': {
              'en': {'subject': 'Hi'},
            },
          }),
        ),
      );
      expect(saveTemplate.statusCode, 200);

      final getTemplates = await router.handler(
        Request(
          'GET',
          Uri.parse('http://localhost/auth/admin/api/templates/mail'),
          headers: {'authorization': 'Bearer $accessToken'},
        ),
      );
      final templatesBody = _jsonBody(await getTemplates.readAsString());
      expect(getTemplates.statusCode, 200);
      expect(templatesBody['templates'], isA<List<dynamic>>());
    });

    test('hides IdP endpoints when enableIdpMode is false', () async {
      final noIdpConfig = config.copyWith(enableIdpMode: false);
      final noIdpRouter = AuthRouter(config: noIdpConfig, authService: service);

      final discoveryResponse = await noIdpRouter.handler(
        Request('GET', Uri.parse('http://localhost/auth/.well-known/openid-configuration')),
      );
      final jwksResponse = await noIdpRouter.handler(
        Request('GET', Uri.parse('http://localhost/auth/jwks')),
      );
      final userInfoResponse = await noIdpRouter.handler(
        Request(
          'GET',
          Uri.parse('http://localhost/auth/userinfo'),
          headers: const {'authorization': 'Bearer fake-token'},
        ),
      );
      final tokenResponse = await noIdpRouter.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/token'),
          body: jsonEncode(const {'userId': 'demo'}),
          headers: const {'content-type': 'application/json'},
        ),
      );

      expect(discoveryResponse.statusCode, 404);
      expect(jwksResponse.statusCode, 404);
      expect(userInfoResponse.statusCode, 404);
      expect(tokenResponse.statusCode, 404);
    });

    test('resets password via token store using POST /auth/reset-password', () async {
      final registerResponse = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/register'),
          body: jsonEncode({
            'email': 'reset-user@example.com',
            'password': 'OldPassword1!',
          }),
          headers: const {'content-type': 'application/json'},
        ),
      );
      final registerBody = _jsonBody(await registerResponse.readAsString());
      final user = registerBody['user'] as Map<String, dynamic>;

      await tokenStore.save(
        TokenRecord(
          token: 'reset-token',
          purpose: 'password_reset',
          userId: user['id'] as String,
          email: user['email'] as String,
          createdAt: DateTime.now().toUtc(),
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );

      final resetResponse = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/reset-password'),
          body: jsonEncode({
            'token': 'reset-token',
            'newPassword': 'NewPassword1!',
          }),
          headers: const {'content-type': 'application/json'},
        ),
      );
      expect(resetResponse.statusCode, 200);

      final loginResponse = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/login'),
          body: jsonEncode({
            'email': 'reset-user@example.com',
            'password': 'NewPassword1!',
          }),
          headers: const {'content-type': 'application/json'},
        ),
      );
      expect(loginResponse.statusCode, 200);
    });

    test('verifies email from GET /auth/verify-email token', () async {
      final registerResponse = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/register'),
          body: jsonEncode({
            'email': 'verify-user@example.com',
            'password': 'StrongPass1!',
          }),
          headers: const {'content-type': 'application/json'},
        ),
      );
      final registerBody = _jsonBody(await registerResponse.readAsString());
      final user = registerBody['user'] as Map<String, dynamic>;
      final userId = user['id'] as String;

      await tokenStore.save(
        TokenRecord(
          token: 'verify-token',
          purpose: 'verify_email',
          userId: userId,
          email: 'verify-user@example.com',
          createdAt: DateTime.now().toUtc(),
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
        ),
      );

      final verifyResponse = await router.handler(
        Request(
          'GET',
          Uri.parse('http://localhost/auth/verify-email?token=verify-token'),
        ),
      );
      expect(verifyResponse.statusCode, 200);

      final saved = await userStore.findById(userId);
      expect(saved, isNotNull);
      expect(saved!.emailVerified, isTrue);
    });

    test('confirms change-email via token', () async {
      final registerResponse = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/register'),
          body: jsonEncode({
            'email': 'before-change@example.com',
            'password': 'StrongPass1!',
          }),
          headers: const {'content-type': 'application/json'},
        ),
      );
      final registerBody = _jsonBody(await registerResponse.readAsString());
      final user = registerBody['user'] as Map<String, dynamic>;
      final userId = user['id'] as String;

      await tokenStore.save(
        TokenRecord(
          token: 'change-token',
          purpose: 'change_email',
          userId: userId,
          email: 'before-change@example.com',
          newEmail: 'after-change@example.com',
          createdAt: DateTime.now().toUtc(),
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
        ),
      );

      final confirmResponse = await router.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/auth/change-email/confirm'),
          body: jsonEncode({'token': 'change-token'}),
          headers: const {'content-type': 'application/json'},
        ),
      );
      expect(confirmResponse.statusCode, 200);

      final updated = await userStore.findById(userId);
      expect(updated, isNotNull);
      expect(updated!.email, 'after-change@example.com');
      expect(updated.emailVerified, isTrue);
    });

    test('openapi.json lists the full route surface', () async {
      final response = await router.handler(
        Request('GET', Uri.parse('http://localhost/auth/openapi.json')),
      );
      final body = _jsonBody(await response.readAsString());
      final paths = body['paths'] as Map<String, dynamic>;

      expect(paths.keys, contains('/auth/login'));
      expect(paths.keys, contains('/auth/register'));
      expect(paths.keys, contains('/auth/refresh'));
      expect(paths.keys, contains('/auth/me'));
      expect(paths.keys, contains('/auth/logout'));
      expect(paths.keys, contains('/auth/2fa/setup'));
      expect(paths.keys, contains('/auth/magic-link/send'));
    });

    test('openapi.json omits IdP routes when enableIdpMode is false', () async {
      final noIdpConfig = config.copyWith(enableIdpMode: false);
      final noIdpRouter = AuthRouter(config: noIdpConfig, authService: service);

      final response = await noIdpRouter.handler(
        Request('GET', Uri.parse('http://localhost/auth/openapi.json')),
      );
      final body = _jsonBody(await response.readAsString());
      final paths = body['paths'] as Map<String, dynamic>;

      expect(paths.keys, isNot(contains('/auth/.well-known/openid-configuration')));
      expect(paths.keys, isNot(contains('/auth/jwks')));
      expect(paths.keys, isNot(contains('/auth/userinfo')));
      expect(paths.keys, isNot(contains('/auth/token')));
    });
  });
}
