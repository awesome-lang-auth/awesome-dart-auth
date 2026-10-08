import 'package:awesome_dart_auth/awesome_dart_auth.dart';
import 'package:awesome_dart_auth_shelf/awesome_dart_auth_shelf.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class _UserStore implements UserStore {
  @override
  Future<AuthUser?> findByEmail(String email) async => null;

  @override
  Future<AuthUser?> findById(String id) async => null;

  @override
  Future<AuthUser> save(AuthUser user) async => user;

  @override
  Future<AuthUser> update(AuthUser user) async => user;

  @override
  Future<void> delete(String id) async {}
}

class _SessionStore implements SessionStore {
  @override
  Future<AuthSession?> findById(String id) async => null;

  @override
  Future<void> revoke(String id) async {}

  @override
  Future<void> save(AuthSession session) async {}
}

void main() {
  test('middleware serves auth routes before the downstream handler', () async {
    final config = AuthConfig.development(jwtSecret: 'secret1234');
    final router = AuthRouter(
      config: config,
      authService: AuthService(
        config: config,
        userStore: _UserStore(),
        sessionStore: _SessionStore(),
      ),
    );

    final handler = const Pipeline()
        .addMiddleware(awesomeDartAuthShelfMiddleware(router))
        .addHandler((_) => Response.ok('downstream'));

    final response = await handler(
      Request('GET', Uri.parse('http://localhost/auth/ui/login')),
    );

    expect(response.statusCode, 200);
  });
}
