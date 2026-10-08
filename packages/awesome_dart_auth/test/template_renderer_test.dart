import 'package:awesome_dart_auth/awesome_dart_auth.dart';
import 'package:test/test.dart';

void main() {
  test('falls back to the default locale', () {
    final renderer = TemplateRenderer(
      config: AuthConfig.development(jwtSecret: 'secret1234'),
    );

    final result = renderer.render(
      templateName: 'welcome',
      locale: 'fr',
      context: const {'loginUrl': 'https://example.com/login'},
    );

    expect(result, contains('Your account has been created successfully'));
    expect(result, contains('example.com'));
  });

  test('renders newly ported built-in templates', () {
    final renderer = TemplateRenderer(
      config: AuthConfig.development(jwtSecret: 'secret1234'),
    );

    final reset = renderer.render(
      templateName: 'password_reset',
      context: const {'link': 'https://example.com/reset?token=abc'},
    );
    final verify = renderer.render(
      templateName: 'verify_email',
      locale: 'it',
      context: const {'link': 'https://example.com/verify?token=xyz'},
    );

    expect(reset, contains('Click the link below to proceed'));
    expect(verify, contains('verificare il tuo indirizzo email'));
  });
}
