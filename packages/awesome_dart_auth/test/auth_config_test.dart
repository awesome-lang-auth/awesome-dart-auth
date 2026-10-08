import 'package:awesome_dart_auth/awesome_dart_auth.dart';
import 'package:test/test.dart';

void main() {
  group('AuthConfig', () {
    test('copyWith preserves and overrides values', () {
      final config = AuthConfig.development(jwtSecret: 'secret1234');

      final updated = config.copyWith(
        issuer: 'https://auth.example.com',
        supportedLocales: const {'en', 'it', 'fr'},
        defaultLocale: 'fr',
      );

      expect(updated.jwtSecret, 'secret1234');
      expect(updated.issuer, 'https://auth.example.com');
      expect(updated.defaultLocale, 'fr');
      expect(updated.supportedLocales, contains('fr'));
    });

    group('UI paths', () {
      test('default to /auth/ui and /auth/ui/auth.js', () {
        final config = AuthConfig.development(jwtSecret: 'secret1234');

        expect(config.apiBasePath, '/auth');
        expect(config.authUiPath, '/auth/ui');
        expect(config.authJsPath, '/auth/ui/auth.js');
      });

      test('follow apiBasePath when only apiBasePath is set', () {
        final config = AuthConfig(
          jwtSecret: 'secret1234',
          issuer: 'https://auth.example.com',
          apiBasePath: '/api/auth',
        );

        expect(config.authUiPath, '/api/auth/ui');
        expect(config.authJsPath, '/api/auth/ui/auth.js');
      });

      test('keep explicit overrides', () {
        final config = AuthConfig(
          jwtSecret: 'secret1234',
          issuer: 'https://auth.example.com',
          apiBasePath: '/api/auth',
          authUiPath: '/login-ui',
          authJsPath: '/static/auth.js',
        );

        expect(config.authUiPath, '/login-ui');
        expect(config.authJsPath, '/static/auth.js');
      });

      test('authJsPath follows an explicit authUiPath', () {
        final config = AuthConfig(
          jwtSecret: 'secret1234',
          issuer: 'https://auth.example.com',
          authUiPath: '/login-ui',
        );

        expect(config.authUiPath, '/login-ui');
        expect(config.authJsPath, '/login-ui/auth.js');
      });

      test('copyWith(apiBasePath:) derives them again', () {
        final config = AuthConfig.development(
          jwtSecret: 'secret1234',
        ).copyWith(apiBasePath: '/api/auth');

        expect(config.authUiPath, '/api/auth/ui');
        expect(config.authJsPath, '/api/auth/ui/auth.js');
      });

      test('copyWith keeps explicit overrides', () {
        final config = AuthConfig(
          jwtSecret: 'secret1234',
          issuer: 'https://auth.example.com',
          authUiPath: '/login-ui',
          authJsPath: '/static/auth.js',
        ).copyWith(apiBasePath: '/api/auth');

        expect(config.authUiPath, '/login-ui');
        expect(config.authJsPath, '/static/auth.js');
      });
    });

    test('throws when no token transport is enabled', () {
      expect(
        () => AuthConfig(
          jwtSecret: 'secret1234',
          issuer: 'https://auth.example.com',
          allowBearerTokens: false,
          allowCookieTokens: false,
        ),
        throwsArgumentError,
      );
    });
  });
}
