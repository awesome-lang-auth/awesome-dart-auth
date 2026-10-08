import 'dart:convert';
import 'dart:math';

import 'package:awesome_dart_auth/src/config/auth_callbacks.dart';
import 'package:awesome_dart_auth/src/config/auth_config.dart';
import 'package:awesome_dart_auth/src/contracts/admin_session_store.dart';
import 'package:awesome_dart_auth/src/contracts/admin_user_store.dart';
import 'package:awesome_dart_auth/src/contracts/api_key_store.dart';
import 'package:awesome_dart_auth/src/contracts/template_store.dart';
import 'package:awesome_dart_auth/src/contracts/tenant_store.dart';
import 'package:awesome_dart_auth/src/contracts/token_store.dart';
import 'package:awesome_dart_auth/src/idp/openid_endpoints.dart';
import 'package:awesome_dart_auth/src/models/api_key_record.dart';
import 'package:awesome_dart_auth/src/models/auth_user.dart';
import 'package:awesome_dart_auth/src/models/tenant_record.dart';
import 'package:awesome_dart_auth/src/models/token_record.dart';
import 'package:awesome_dart_auth/src/routing/openapi_document.dart';
import 'package:awesome_dart_auth/src/services/auth_service.dart';
import 'package:awesome_dart_auth/src/templates/template_renderer.dart';
import 'package:awesome_dart_auth/src/ui/embedded_assets.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Shelf router exposing the built-in awesome-dart-auth endpoints.
class AuthRouter {
  /// Creates the auth router.
  AuthRouter({
    required this.config,
    required this.authService,
    this.tokenStore,
    this.tenantStore,
    this.apiKeyStore,
    this.templateStore,
    TemplateRenderer? templateRenderer,
    AuthCallbacks? callbacks,
  }) : templateRenderer =
           templateRenderer ?? TemplateRenderer(config: config),
       callbacks = callbacks ?? const AuthCallbacks() {
    _registerRoutes();
  }

  /// Runtime auth configuration.
  final AuthConfig config;

  /// Core auth service.
  final AuthService authService;

  /// Optional store for temporary verification and reset tokens.
  final TokenStore? tokenStore;

  /// Optional tenant store for admin panel tenant management.
  final TenantStore? tenantStore;

  /// Optional API key store for admin API key management.
  final ApiKeyStore? apiKeyStore;

  /// Optional template store for dynamic template overrides.
  final TemplateStore? templateStore;

  /// Template renderer backing localized mail rendering.
  final TemplateRenderer templateRenderer;

  /// Optional side-effect callbacks for auth flows.
  final AuthCallbacks callbacks;

  final Map<String, Set<String>> _rolePermissions = <String, Set<String>>{};
  final Map<String, Map<String, Object?>> _userMetadata =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> _mailTemplates =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, String>> _uiTranslations =
      <String, Map<String, String>>{};
  final Map<String, Set<String>> _tenantMembers = <String, Set<String>>{};
  final Map<String, ApiKeyRecord> _apiKeys = <String, ApiKeyRecord>{};
  final Map<String, String> _apiKeyNames = <String, String>{};
  final Map<String, Object?> _adminSettings = <String, Object?>{
    'requireEmailVerification': false,
    'require2FA': false,
    'emailVerificationMode': 'none',
    'lazyEmailVerificationGracePeriodDays': 7,
    'enabledWebhookActions': <String>[],
    'ui': <String, Object?>{},
  };

  final Router _router = Router();

  /// Returns the underlying Shelf handler.
  Handler get handler => _router.call;

  void _registerRoutes() {
    _router
      ..get('/health', (_) => _ok({'status': 'ok'}))
      ..get(config.adminUiPath, (_) {
        if (!config.enableAdminUi) {
          return Response.notFound('admin ui disabled');
        }
        return Response.ok(
          _buildAdminUiHtml(),
          headers: const {'content-type': 'text/html; charset=utf-8'},
        );
      })
      ..get('${config.adminUiPath}/assets/admin.js', (_) {
        if (!config.enableAdminUi) {
          return Response.notFound('admin ui disabled');
        }
        return Response.ok(
          embeddedAdminJs,
          headers: const {
            'content-type': 'application/javascript; charset=utf-8',
          },
        );
      })
      ..get('${config.adminUiPath}/assets/admin.css', (_) {
        if (!config.enableAdminUi) {
          return Response.notFound('admin ui disabled');
        }
        return Response.ok(
          embeddedAdminCss,
          headers: const {'content-type': 'text/css; charset=utf-8'},
        );
      })
      ..get(config.authUiPath, (_) {
        if (!config.enableAuthUi) {
          return Response.notFound('auth ui disabled');
        }
        return Response.found('${config.authUiPath}/login');
      })
      ..get('${config.authUiPath}/login', (_) {
        if (!config.enableAuthUi) {
          return Response.notFound('auth ui disabled');
        }
        return Response.ok(
          embeddedAuthUi,
          headers: const {'content-type': 'text/html; charset=utf-8'},
        );
      })
      ..get(
        config.authJsPath,
        (_) => Response.ok(
          embeddedAuthJs,
          headers: const {
            'content-type': 'application/javascript; charset=utf-8',
          },
        ),
      )
      ..get('${config.apiBasePath}/ui/base.css', (_) {
        if (!config.enableAuthUi) {
          return Response.notFound('auth ui disabled');
        }
        return Response.ok(
          embeddedAuthBaseCss,
          headers: const {'content-type': 'text/css; charset=utf-8'},
        );
      })
      ..get(
        '${config.apiBasePath}/ui/config',
        (Request request) => _ok(_buildUiConfig(request)),
      )
      ..get(config.openApiPath, (_) => _ok(buildOpenApiDocument(config)))
      ..get(config.discoveryPath, (_) {
        if (!config.enableIdpMode) {
          return Response.notFound('idp mode disabled');
        }
        return _ok(openIdDiscoveryDocument(config));
      })
      ..get(config.jwksPath, (_) {
        if (!config.enableIdpMode) {
          return Response.notFound('idp mode disabled');
        }
        return _ok(jsonWebKeySet());
      })
      ..get(config.userInfoPath, (Request request) {
        if (!config.enableIdpMode) {
          return Response.notFound('idp mode disabled');
        }
        final token = _extractBearer(request);
        if (token == null) return Response.forbidden('missing bearer token');
        final claims = authService.verifyToken(token);
        return _ok(<String, Object?>{
          'sub': claims['sub'],
          'email': claims['email'],
          'tenantId': claims['tenantId'],
          'roles': claims['roles'] is List
              ? claims['roles']! as List<Object?>
              : const <Object?>[],
        });
      })
      ..post(config.tokenPath, (Request request) async {
        if (!config.enableIdpMode) {
          return Response.notFound('idp mode disabled');
        }
        final payload = await _readJson(request);
        final user = AuthUser(
          id: (payload['userId'] as String?) ?? 'demo-user',
          email: (payload['email'] as String?) ?? 'demo@example.com',
          tenantId: payload['tenantId'] as String?,
          roles: _stringList(payload['roles']),
          providers: _stringList(payload['providers']),
        );
        final tokenPair = await authService.issueTokenPair(
          user: user,
          scopes: Set<String>.from(_stringList(payload['scopes'])),
        );
        return _ok(tokenPair.toJson());
      });

    _registerSessionRoutes();
    _registerAccountRoutes();
    _register2faRoutes();
    _registerMagicLinkRoutes();
    _registerSmsRoutes();
    _registerDeviceSessionRoutes();
    _registerOAuthRoutes();
    _registerLinkingRoutes();
    _registerAdminApiRoutes();
  }

  // ---------------------------------------------------------------------------
  // Session (login / register / logout / me / refresh)
  // ---------------------------------------------------------------------------

  void _registerSessionRoutes() {
    _router
      ..post('${config.apiBasePath}/register', (Request request) async {
        final body = await _readJson(request);
        final email = body['email'] as String?;
        final password = body['password'] as String?;
        if (email == null || email.isEmpty) {
          return _badRequest('email is required');
        }
        if (password == null || password.isEmpty) {
          return _badRequest('password is required');
        }
        try {
          var user = await authService.register(
            email: email,
            password: password,
            firstName: body['firstName'] as String?,
            lastName: body['lastName'] as String?,
          );
          final onRegister = callbacks.onRegister;
          if (onRegister != null) user = await onRegister(user);
          final tokenPair = await authService.issueTokenPair(
            user: user,
            userAgent: request.headers['user-agent'],
          );
          return _ok(<String, Object?>{
            'user': _userPayload(user),
            ...tokenPair.toJson(),
          });
        } on RegistrationException catch (e) {
          return _badRequest(e.message);
        }
      })
      ..post('${config.apiBasePath}/login', (Request request) async {
        final body = await _readJson(request);
        final email = body['email'] as String?;
        final password = body['password'] as String?;
        if (email == null || password == null) {
          return _badRequest('email and password are required');
        }
        try {
          final user =
              await authService.login(email: email, password: password);
          if (user.totpEnabled) {
            return _ok(<String, Object?>{
              'requiresTwoFactor': true,
              'userId': user.id,
            });
          }
          final tokenPair = await authService.issueTokenPair(
            user: user,
            userAgent: request.headers['user-agent'],
          );
          return _ok(<String, Object?>{
            'user': _userPayload(user),
            ...tokenPair.toJson(),
          });
        } on AuthenticationException catch (e) {
          return _authError(e.message);
        }
      })
      ..post('${config.apiBasePath}/logout', (Request request) async {
        final token = _extractBearer(request);
        if (token != null) {
          try {
            final claims = authService.verifyToken(token);
            final sid = claims['sid'] as String?;
            if (sid != null) await authService.sessionStore.revoke(sid);
          } on JWTException {
            // Ignore invalid tokens during logout.
          }
        }
        return _ok({'ok': true});
      })
      ..get('${config.apiBasePath}/me', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        return _ok(_userPayload(user));
      })
      ..post('${config.apiBasePath}/refresh', (Request request) async {
        final body = await _readJson(request);
        final refreshToken = body['refreshToken'] as String?;
        if (refreshToken == null || refreshToken.isEmpty) {
          return _badRequest('refreshToken is required');
        }
        try {
          final tokenPair =
              await authService.refreshTokenPair(refreshToken);
          return _ok(tokenPair.toJson());
        } on AuthenticationException catch (e) {
          return _authError(e.message);
        }
      });
  }

  // ---------------------------------------------------------------------------
  // Account management
  // ---------------------------------------------------------------------------

  void _registerAccountRoutes() {
    _router
      ..patch('${config.apiBasePath}/profile', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final body = await _readJson(request);
        final updated = user.copyWith(
          firstName: body.containsKey('firstName')
              ? body['firstName'] as String?
              : user.firstName,
          lastName: body.containsKey('lastName')
              ? body['lastName'] as String?
              : user.lastName,
          updatedAt: DateTime.now().toUtc(),
        );
        final saved = await authService.userStore.update(updated);
        return _ok(_userPayload(saved));
      })
      ..delete('${config.apiBasePath}/account', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        await authService.userStore.delete(user.id);
        return _ok({'ok': true});
      })
      ..post(
        '${config.apiBasePath}/forgot-password',
        (Request request) async {
          final body = await _readJson(request);
          final email = body['email'] as String?;
          if (email == null) return _badRequest('email is required');
          final user = await authService.userStore.findByEmail(email);
          if (user != null) {
            final token = authService.generateRandomToken();
            final store = tokenStore;
            if (store != null) {
              await store.save(
                TokenRecord(
                  token: token,
                  purpose: 'password_reset',
                  userId: user.id,
                  email: user.email,
                  createdAt: DateTime.now().toUtc(),
                  expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
                ),
              );
            }
            final cb = callbacks.onForgotPassword;
            if (cb == null) {
              return _notImplemented(
                'onForgotPassword callback not configured',
              );
            }
            await cb(user, token);
          }
          return _ok({'ok': true});
        },
      )
      ..post('${config.apiBasePath}/reset-password', (Request request) async {
        final store = tokenStore;
        if (store == null) {
          return _notImplemented(
            'Supply a TokenStore to enable password reset.',
          );
        }
        final body = await _readJson(request);
        final token = body['token'] as String?;
        final newPassword = body['newPassword'] as String?;
        if (token == null || newPassword == null) {
          return _badRequest('token and newPassword are required');
        }
        final record = await store.findByToken(token);
        if (!_isUsableToken(record, purpose: 'password_reset')) {
          return _authError('Invalid or expired password reset token.');
        }
        final user = await authService.userStore.findById(record!.userId);
        if (user == null) {
          return _authError('Invalid password reset token.');
        }
        await authService.userStore.update(
          user.copyWith(
            passwordHash: authService.hashPassword(newPassword),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
        await store.consume(token);
        return _ok({'ok': true});
      })
      ..post(
        '${config.apiBasePath}/change-password',
        (Request request) async {
          final user = await _requireAuth(request);
          if (user == null) return _unauthorized();
          final body = await _readJson(request);
          final currentPassword = body['currentPassword'] as String?;
          final newPassword = body['newPassword'] as String?;
          if (currentPassword == null || newPassword == null) {
            return _badRequest(
              'currentPassword and newPassword are required',
            );
          }
          final hash = user.passwordHash;
          if (hash == null ||
              !authService.verifyPassword(currentPassword, hash)) {
            return _authError('Current password is incorrect.');
          }
          final updated = user.copyWith(
            passwordHash: authService.hashPassword(newPassword),
            updatedAt: DateTime.now().toUtc(),
          );
          await authService.userStore.update(updated);
          return _ok({'ok': true});
        },
      )
      ..post(
        '${config.apiBasePath}/send-verification-email',
        (Request request) async {
          final user = await _requireAuth(request);
          if (user == null) return _unauthorized();
          final cb = callbacks.onSendVerificationEmail;
          if (cb == null) {
            return _notImplemented(
              'onSendVerificationEmail callback not configured',
            );
          }
          final token = authService.generateRandomToken();
          final store = tokenStore;
          if (store != null) {
            await store.save(
              TokenRecord(
                token: token,
                purpose: 'verify_email',
                userId: user.id,
                email: user.email,
                createdAt: DateTime.now().toUtc(),
                expiresAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
              ),
            );
          }
          await cb(user, token);
          return _ok({'ok': true});
        },
      )
      ..get('${config.apiBasePath}/verify-email', (Request request) async {
        final store = tokenStore;
        if (store == null) {
          return _notImplemented(
            'Supply a TokenStore to enable email verification.',
          );
        }
        final token = request.url.queryParameters['token'];
        if (token == null || token.isEmpty) {
          return _badRequest('token query parameter is required');
        }
        final record = await store.findByToken(token);
        if (!_isUsableToken(record, purpose: 'verify_email')) {
          return _authError('Invalid or expired verification token.');
        }
        final user = await authService.userStore.findById(record!.userId);
        if (user == null) {
          return _authError('Invalid verification token.');
        }
        await authService.userStore.update(
          user.copyWith(
            emailVerified: true,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
        await store.consume(token);
        return _ok({'ok': true});
      })
      ..post(
        '${config.apiBasePath}/change-email/request',
        (Request request) async {
          final user = await _requireAuth(request);
          if (user == null) return _unauthorized();
          final body = await _readJson(request);
          final newEmail = body['newEmail'] as String?;
          if (newEmail == null) return _badRequest('newEmail is required');
          final cb = callbacks.onSendVerificationEmail;
          if (cb == null) {
            return _notImplemented(
              'onSendVerificationEmail callback not configured',
            );
          }
          final token = authService.generateRandomToken();
          final store = tokenStore;
          if (store != null) {
            await store.save(
              TokenRecord(
                token: token,
                purpose: 'change_email',
                userId: user.id,
                email: user.email,
                newEmail: newEmail,
                createdAt: DateTime.now().toUtc(),
                expiresAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
              ),
            );
          }
          await cb(user, token);
          return _ok({'ok': true});
        },
      )
      ..post(
        '${config.apiBasePath}/change-email/confirm',
        (Request request) async {
          final store = tokenStore;
          if (store == null) {
            return _notImplemented(
              'Supply a TokenStore to enable email-change confirmation.',
            );
          }
          final body = await _readJson(request);
          final token = body['token'] as String?;
          if (token == null || token.isEmpty) {
            return _badRequest('token is required');
          }
          final record = await store.findByToken(token);
          if (!_isUsableToken(record, purpose: 'change_email')) {
            return _authError('Invalid or expired change-email token.');
          }
          final nextEmail = record!.newEmail;
          if (nextEmail == null || nextEmail.isEmpty) {
            return _badRequest('change-email token does not contain newEmail');
          }
          final existing = await authService.userStore.findByEmail(nextEmail);
          if (existing != null && existing.id != record.userId) {
            return _badRequest('Email already in use');
          }
          final user = await authService.userStore.findById(record.userId);
          if (user == null) {
            return _authError('Invalid change-email token.');
          }
          await authService.userStore.update(
            user.copyWith(
              email: nextEmail,
              emailVerified: true,
              updatedAt: DateTime.now().toUtc(),
            ),
          );
          await store.consume(token);
          return _ok({'ok': true});
        },
      );
  }

  // ---------------------------------------------------------------------------
  // TOTP / 2FA
  // ---------------------------------------------------------------------------

  void _register2faRoutes() {
    _router
      ..post('${config.apiBasePath}/2fa/setup', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final secret = authService.generateTotpSecret();
        return _ok(<String, Object?>{
          'secret': secret,
          'otpAuthUrl':
              'otpauth://totp/'
              '${Uri.encodeComponent(config.issuer)}'
              ':${Uri.encodeComponent(user.email)}'
              '?secret=$secret'
              '&issuer=${Uri.encodeComponent(config.issuer)}',
        });
      })
      ..post(
        '${config.apiBasePath}/2fa/verify-setup',
        (Request request) async {
          final user = await _requireAuth(request);
          if (user == null) return _unauthorized();
          final body = await _readJson(request);
          final secret = body['secret'] as String?;
          final code = body['code'] as String?;
          if (secret == null || code == null) {
            return _badRequest('secret and code are required');
          }
          if (!authService.verifyTotpCode(secret, code)) {
            return _badRequest('Invalid TOTP code');
          }
          await authService.userStore.update(
            user.copyWith(
              totpSecret: secret,
              totpEnabled: true,
              updatedAt: DateTime.now().toUtc(),
            ),
          );
          return _ok({'ok': true});
        },
      )
      ..post('${config.apiBasePath}/2fa/verify', (Request request) async {
        final body = await _readJson(request);
        final userId = body['userId'] as String?;
        final code = body['code'] as String?;
        if (userId == null || code == null) {
          return _badRequest('userId and code are required');
        }
        final user = await authService.userStore.findById(userId);
        if (user == null) return _unauthorized();
        final secret = user.totpSecret;
        if (secret == null || !user.totpEnabled) {
          return _badRequest('TOTP not enabled for this user');
        }
        if (!authService.verifyTotpCode(secret, code)) {
          return _authError('Invalid TOTP code.');
        }
        final tokenPair = await authService.issueTokenPair(
          user: user,
          userAgent: request.headers['user-agent'],
        );
        return _ok(<String, Object?>{
          'user': _userPayload(user),
          ...tokenPair.toJson(),
        });
      })
      ..post('${config.apiBasePath}/2fa/disable', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        await authService.userStore.update(
          user.copyWith(
            totpSecret: null,
            totpEnabled: false,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
        return _ok({'ok': true});
      });
  }

  // ---------------------------------------------------------------------------
  // Magic link
  // ---------------------------------------------------------------------------

  void _registerMagicLinkRoutes() {
    _router
      ..post(
        '${config.apiBasePath}/magic-link/send',
        (Request request) async {
          final body = await _readJson(request);
          final email = body['email'] as String?;
          if (email == null) return _badRequest('email is required');
          final user = await authService.userStore.findByEmail(email);
          if (user != null) {
            final cb = callbacks.onMagicLinkSend;
            if (cb == null) {
              return _notImplemented(
                'onMagicLinkSend callback not configured',
              );
            }
            await cb(user, authService.generateRandomToken());
          }
          return _ok({'ok': true});
        },
      )
      ..post(
        '${config.apiBasePath}/magic-link/verify',
        (Request request) async {
          final body = await _readJson(request);
          final token = body['token'] as String?;
          final mode = (body['mode'] as String?) ?? 'login';
          if (token == null) return _badRequest('token is required');
          final cb = callbacks.onMagicLinkVerify;
          if (cb == null) {
            return _notImplemented(
              'onMagicLinkVerify callback not configured',
            );
          }
          final userId = await cb(token, mode);
          if (userId == null) {
            return _authError('Invalid or expired magic link.');
          }
          final user = await authService.userStore.findById(userId);
          if (user == null) return _unauthorized();
          final tokenPair = await authService.issueTokenPair(
            user: user,
            userAgent: request.headers['user-agent'],
          );
          return _ok(<String, Object?>{
            'user': _userPayload(user),
            ...tokenPair.toJson(),
          });
        },
      );
  }

  // ---------------------------------------------------------------------------
  // SMS OTP
  // ---------------------------------------------------------------------------

  void _registerSmsRoutes() {
    _router
      ..post('${config.apiBasePath}/sms/send', (Request request) async {
        final body = await _readJson(request);
        final email = body['email'] as String?;
        if (email == null) return _badRequest('email is required');
        final user = await authService.userStore.findByEmail(email);
        if (user != null) {
          final cb = callbacks.onSmsSend;
          if (cb == null) {
            return _notImplemented('onSmsSend callback not configured');
          }
          await cb(user, _sixDigitOtp());
        }
        return _ok({'ok': true});
      })
      ..post('${config.apiBasePath}/sms/verify', (Request request) async {
        final body = await _readJson(request);
        final email = body['email'] as String?;
        final code = body['code'] as String?;
        if (email == null || code == null) {
          return _badRequest('email and code are required');
        }
        final user = await authService.userStore.findByEmail(email);
        if (user == null) return _unauthorized();
        final cb = callbacks.onSmsVerify;
        if (cb == null) {
          return _notImplemented('onSmsVerify callback not configured');
        }
        if (!await cb(user, code)) return _authError('Invalid OTP code.');
        final tokenPair = await authService.issueTokenPair(
          user: user,
          userAgent: request.headers['user-agent'],
        );
        return _ok(<String, Object?>{
          'user': _userPayload(user),
          ...tokenPair.toJson(),
        });
      })
      ..post('${config.apiBasePath}/add-phone', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final body = await _readJson(request);
        final phone = body['phoneNumber'] as String?;
        if (phone == null) return _badRequest('phoneNumber is required');
        await authService.userStore.update(
          user.copyWith(
            phoneNumber: phone,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
        return _ok({'ok': true});
      });
  }

  // ---------------------------------------------------------------------------
  // Device / session management
  // ---------------------------------------------------------------------------

  void _registerDeviceSessionRoutes() {
    _router
      ..get('${config.apiBasePath}/sessions', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        return _ok(<String, Object?>{
          'sessions': <Object?>[],
          'note':
              'Implement listByUserId on your SessionStore to populate '
              'this list.',
        });
      })
      ..delete(
        '${config.apiBasePath}/sessions/<handle>',
        (Request request, String handle) async {
          final user = await _requireAuth(request);
          if (user == null) return _unauthorized();
          await authService.sessionStore.revoke(handle);
          return _ok({'ok': true});
        },
      );
  }

  // ---------------------------------------------------------------------------
  // OAuth
  // ---------------------------------------------------------------------------

  void _registerOAuthRoutes() {
    _router
      ..get(
        '${config.apiBasePath}/oauth/<provider>',
        (Request request, String provider) async {
          final cb = callbacks.onOAuthStart;
          if (cb == null) {
            return _notImplemented('onOAuthStart callback not configured');
          }
          final redirectUri =
              request.url.queryParameters['redirect_uri'] ?? '';
          return Response.found(await cb(provider, redirectUri));
        },
      )
      ..get(
        '${config.apiBasePath}/oauth/<provider>/callback',
        (Request request, String provider) async {
          final cb = callbacks.onOAuthCallback;
          if (cb == null) {
            return _notImplemented(
              'onOAuthCallback callback not configured',
            );
          }
          final code = request.url.queryParameters['code'] ?? '';
          final redirectUri =
              request.url.queryParameters['redirect_uri'] ?? '';
          final profile = await cb(provider, code, redirectUri);
          AuthUser? user;
          if (profile.email != null) {
            user = await authService.userStore.findByEmail(profile.email!);
          }
          user ??= await authService.userStore.save(
            AuthUser(
              id: authService.generateRandomToken(byteLength: 12),
              email: profile.email ??
                  '${profile.externalId}@${profile.provider}.oauth',
              providers: [profile.provider],
              createdAt: DateTime.now().toUtc(),
            ),
          );
          final tokenPair = await authService.issueTokenPair(
            user: user,
            userAgent: request.headers['user-agent'],
          );
          return _ok(<String, Object?>{
            'user': _userPayload(user),
            ...tokenPair.toJson(),
          });
        },
      );
  }

  // ---------------------------------------------------------------------------
  // Account linking
  // ---------------------------------------------------------------------------

  void _registerLinkingRoutes() {
    _router
      ..post(
        '${config.apiBasePath}/link-request',
        (Request request) async {
          final user = await _requireAuth(request);
          if (user == null) return _unauthorized();
          final body = await _readJson(request);
          final provider = body['provider'] as String?;
          if (provider == null) return _badRequest('provider is required');
          final cb = callbacks.onLinkRequest;
          if (cb == null) {
            return _notImplemented('onLinkRequest callback not configured');
          }
          return _ok({'token': await cb(user, provider, body)});
        },
      )
      ..post(
        '${config.apiBasePath}/link-verify',
        (Request request) async {
          final user = await _requireAuth(request);
          if (user == null) return _unauthorized();
          final body = await _readJson(request);
          final token = body['token'] as String?;
          final provider = body['provider'] as String?;
          if (token == null || provider == null) {
            return _badRequest('token and provider are required');
          }
          final cb = callbacks.onLinkVerify;
          if (cb == null) {
            return _notImplemented('onLinkVerify callback not configured');
          }
          if (!await cb(user, token, provider)) {
            return _badRequest('Invalid or expired link token');
          }
          return _ok({'ok': true});
        },
      )
      ..get(
        '${config.apiBasePath}/linked-accounts',
        (Request request) async {
          final user = await _requireAuth(request);
          if (user == null) return _unauthorized();
          return _ok({'providers': user.providers});
        },
      )
      ..delete(
        '${config.apiBasePath}/linked-accounts/<provider>/<id>',
        (Request request, String provider, String id) async {
          final user = await _requireAuth(request);
          if (user == null) return _unauthorized();
          await authService.userStore.update(
            user.copyWith(
              providers: user.providers
                  .where((p) => p != provider)
                  .toList(growable: false),
              updatedAt: DateTime.now().toUtc(),
            ),
          );
          return _ok({'ok': true});
        },
      );
  }

  // ---------------------------------------------------------------------------
  // Admin API
  // ---------------------------------------------------------------------------

  void _registerAdminApiRoutes() {
    final base = '${config.adminUiPath}/api';
    _router
      ..get('$base/ping', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        return _ok({'ok': true, 'userId': user.id});
      })
      ..get('$base/users', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final userStore = authService.userStore;
        if (userStore is! AdminUserStore) {
          return _notImplemented(
            'UserStore must implement AdminUserStore for admin listing.',
          );
        }
        final limit = _parseLimit(request);
        final offset = _parseOffset(request);
        final filter = request.url.queryParameters['filter'];
        final result = await userStore.listUsers(
          limit: limit,
          offset: offset,
          filter: filter?.trim().isEmpty ?? true ? null : filter,
        );
        return _ok(<String, Object?>{
          'users': result.users.map(_adminUserPayload).toList(growable: false),
          'total': result.total,
        });
      })
      ..delete('$base/users/<id>', (Request request, String id) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        await authService.userStore.delete(id);
        return _ok({'ok': true});
      })
      ..get('$base/users/<id>/roles', (Request request, String id) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final target = await authService.userStore.findById(id);
        if (target == null) return _badRequest('user not found');
        return _ok({'roles': target.roles});
      })
      ..post('$base/users/<id>/roles', (Request request, String id) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final body = await _readJson(request);
        final role = body['role'] as String?;
        if (role == null || role.trim().isEmpty) {
          return _badRequest('role is required');
        }
        final target = await authService.userStore.findById(id);
        if (target == null) return _badRequest('user not found');
        final next = {...target.roles, role}.toList(growable: false);
        await authService.userStore.update(
          target.copyWith(roles: next, updatedAt: DateTime.now().toUtc()),
        );
        _rolePermissions.putIfAbsent(role, () => <String>{});
        return _ok({'ok': true});
      })
      ..delete(
        '$base/users/<id>/roles/<role>',
        (Request request, String id, String role) async {
          final user = await _requireAuth(request);
          if (user == null) return _unauthorized();
          final target = await authService.userStore.findById(id);
          if (target == null) return _badRequest('user not found');
          final next = target.roles
              .where((r) => r != role)
              .toList(growable: false);
          await authService.userStore.update(
            target.copyWith(roles: next, updatedAt: DateTime.now().toUtc()),
          );
          return _ok({'ok': true});
        },
      )
      ..get('$base/users/<id>/linked-accounts', (
        Request request,
        String id,
      ) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final target = await authService.userStore.findById(id);
        if (target == null) return _badRequest('user not found');
        final linked = target.providers.map((provider) => <String, Object?>{
          'provider': provider,
        }).toList(growable: false);
        return _ok({'linkedAccounts': linked});
      })
      ..get('$base/users/<id>/metadata', (Request request, String id) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        return _ok(_userMetadata[id] ?? <String, Object?>{});
      })
      ..put('$base/users/<id>/metadata', (Request request, String id) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final body = await _readJson(request);
        _userMetadata[id] = Map<String, Object?>.from(body);
        return _ok({'ok': true});
      })
      ..get('$base/roles', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final roles = _rolePermissions.entries
            .map(
              (entry) => <String, Object?>{
                'name': entry.key,
                'permissions': entry.value.toList(growable: false),
              },
            )
            .toList(growable: false);
        return _ok({'roles': roles});
      })
      ..post('$base/roles', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final body = await _readJson(request);
        final name = body['name'] as String?;
        if (name == null || name.trim().isEmpty) {
          return _badRequest('name is required');
        }
        _rolePermissions[name] = _stringList(body['permissions']).toSet();
        return _ok({'ok': true});
      })
      ..delete('$base/roles/<name>', (Request request, String name) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        _rolePermissions.remove(name);
        return _ok({'ok': true});
      })
      ..get('$base/tenants', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final store = tenantStore;
        if (store == null) {
          return _ok({'tenants': <Object?>[]});
        }
        final tenants = await store.listAll();
        return _ok({
          'tenants': tenants.map((t) => t.toJson()).toList(growable: false),
        });
      })
      ..post('$base/tenants', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final store = tenantStore;
        if (store == null) return _notImplemented('TenantStore not configured');
        final body = await _readJson(request);
        final name = body['name'] as String?;
        if (name == null || name.trim().isEmpty) {
          return _badRequest('name is required');
        }
        final id = authService.generateRandomToken(byteLength: 8);
        final saved = await store.save(
          TenantRecord(
            id: id,
            name: name,
            isActive: body['isActive'] as bool? ?? true,
            metadata: const <String, Object?>{},
          ),
        );
        return _ok(saved.toJson());
      })
      ..delete('$base/tenants/<id>', (Request request, String id) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final store = tenantStore;
        if (store == null) return _notImplemented('TenantStore not configured');
        await store.delete(id);
        _tenantMembers.remove(id);
        return _ok({'ok': true});
      })
      ..get('$base/tenants/<id>/users', (Request request, String id) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        return _ok({
          'userIds': (_tenantMembers[id] ?? <String>{}).toList(growable: false),
        });
      })
      ..post('$base/tenants/<id>/users', (Request request, String id) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final body = await _readJson(request);
        final userId = body['userId'] as String?;
        if (userId == null || userId.trim().isEmpty) {
          return _badRequest('userId is required');
        }
        _tenantMembers.putIfAbsent(id, () => <String>{}).add(userId);
        return _ok({'ok': true});
      })
      ..delete(
        '$base/tenants/<tenantId>/users/<userId>',
        (Request request, String tenantId, String userId) async {
          final user = await _requireAuth(request);
          if (user == null) return _unauthorized();
          _tenantMembers[tenantId]?.remove(userId);
          return _ok({'ok': true});
        },
      )
      ..get('$base/users/<id>/tenants', (Request request, String id) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final tenantIds = _tenantMembers.entries
            .where((entry) => entry.value.contains(id))
            .map((entry) => entry.key)
            .toList(growable: false);
        return _ok({'tenantIds': tenantIds});
      })
      ..get('$base/sessions', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final sessionStore = authService.sessionStore;
        if (sessionStore is! AdminSessionStore) {
          return _notImplemented(
            'SessionStore must implement AdminSessionStore for admin sessions.',
          );
        }
        final limit = _parseLimit(request);
        final offset = _parseOffset(request);
        final filter = request.url.queryParameters['filter'];
        final result = await sessionStore.listAllSessions(
          limit: limit,
          offset: offset,
          filter: filter?.trim().isEmpty ?? true ? null : filter,
        );
        return _ok(<String, Object?>{
          'sessions': result.sessions
              .map(
                (s) => <String, Object?>{
                  'sessionHandle': s.handle,
                  'userId': s.userId,
                  'ipAddress': s.ipAddress,
                  'userAgent': s.userAgent,
                  'createdAt': s.createdAt?.toIso8601String(),
                  'lastActiveAt': null,
                  'expiresAt': s.expiresAt.toIso8601String(),
                },
              )
              .toList(growable: false),
          'total': result.total,
        });
      })
      ..delete('$base/sessions/<handle>', (Request request, String handle) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final sessionStore = authService.sessionStore;
        if (sessionStore is AdminSessionStore) {
          await sessionStore.revokeByHandle(handle);
        } else {
          return _notImplemented(
            'SessionStore must implement AdminSessionStore to revoke by handle.',
          );
        }
        return _ok({'ok': true});
      })
      ..get('$base/settings', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        return _ok(Map<String, Object?>.from(_adminSettings));
      })
      ..put('$base/settings', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final body = await _readJson(request);
        _adminSettings.addAll(body);
        return _ok({'ok': true});
      })
      ..patch('$base/settings/ui', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final body = await _readJson(request);
        final currentUi = Map<String, Object?>.from(
          _adminSettings['ui'] as Map<String, Object?>? ?? const <String, Object?>{},
        );
        currentUi.addAll(body);
        _adminSettings['ui'] = currentUi;
        return _ok({'ok': true, 'ui': currentUi});
      })
      ..post('$base/2fa-policy', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final body = await _readJson(request);
        _adminSettings['require2FA'] = body['required'] == true;
        return _ok({'ok': true, 'updated': 0});
      })
      ..get('$base/actions', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        return _ok({'actions': <Object?>[]});
      })
      ..get('$base/templates/mail', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final templates = _mailTemplates.entries
            .map(
              (entry) => <String, Object?>{
                'id': entry.key,
                ...entry.value,
              },
            )
            .toList(growable: false);
        return _ok({'templates': templates});
      })
      ..post('$base/templates/mail', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final body = await _readJson(request);
        final id = body['id'] as String?;
        if (id == null || id.trim().isEmpty) {
          return _badRequest('id is required');
        }
        _mailTemplates[id] = <String, Object?>{
          'baseHtml': body['baseHtml'] as String? ?? '',
          'baseText': body['baseText'] as String? ?? '',
          'translations': Map<String, Object?>.from(
            body['translations'] as Map<dynamic, dynamic>? ??
                const <dynamic, dynamic>{},
          ),
        };
        return _ok({'ok': true});
      })
      ..get('$base/templates/ui', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final list = _uiTranslations.entries
            .map(
              (entry) => <String, Object?>{
                'page': entry.key,
                'translations': entry.value,
              },
            )
            .toList(growable: false);
        return _ok({'translations': list});
      })
      ..post('$base/templates/ui', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final body = await _readJson(request);
        final page = body['page'] as String?;
        if (page == null || page.trim().isEmpty) {
          return _badRequest('page is required');
        }
        final translations = Map<String, String>.from(
          (body['translations'] as Map<dynamic, dynamic>? ??
                  const <dynamic, dynamic>{})
              .map((k, v) => MapEntry(k, '$v')),
        );
        _uiTranslations[page] = translations;
        return _ok({'ok': true});
      })
      ..get('$base/api-keys', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final keys = _apiKeys.values
            .map(
              (k) => <String, Object?>{
                'id': k.id,
                'keyPrefix': k.id.length > 8 ? k.id.substring(0, 8) : k.id,
                'name': _apiKeyNames[k.id] ?? k.id,
                'serviceId': k.tenantId,
                'scopes': k.scopes.toList(growable: false),
                'isActive': !k.revoked,
                'expiresAt': null,
              },
            )
            .toList(growable: false);
        return _ok({'keys': keys, 'total': keys.length});
      })
      ..post('$base/api-keys', (Request request) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final body = await _readJson(request);
        final name = body['name'] as String?;
        if (name == null || name.trim().isEmpty) {
          return _badRequest('name is required');
        }
        final raw = authService.generateRandomToken(byteLength: 24);
        final id = authService.generateRandomToken(byteLength: 10);
        final record = ApiKeyRecord(
          id: id,
          keyHash: authService.hashPassword(raw),
          scopes: Set<String>.from(_stringList(body['scopes'])),
          ipAllowlist: _stringList(body['allowedIps']),
          tenantId: body['serviceId'] as String?,
        );
        _apiKeys[id] = record;
        _apiKeyNames[id] = name;
        final external = apiKeyStore;
        if (external != null) {
          await external.save(record);
        }
        return _ok({'ok': true, 'id': id, 'rawKey': raw});
      })
      ..delete('$base/api-keys/<id>/revoke', (Request request, String id) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        final record = _apiKeys[id];
        if (record != null) {
          _apiKeys[id] = ApiKeyRecord(
            id: record.id,
            keyHash: record.keyHash,
            scopes: record.scopes,
            ipAllowlist: record.ipAllowlist,
            tenantId: record.tenantId,
            revoked: true,
          );
        }
        final external = apiKeyStore;
        if (external != null) {
          await external.revoke(id);
        }
        return _ok({'ok': true});
      })
      ..delete('$base/api-keys/<id>', (Request request, String id) async {
        final user = await _requireAuth(request);
        if (user == null) return _unauthorized();
        _apiKeys.remove(id);
        final external = apiKeyStore;
        if (external != null) {
          await external.revoke(id);
        }
        _apiKeyNames.remove(id);
        return _ok({'ok': true});
      });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Response _ok(Map<String, Object?> payload) => Response.ok(
    jsonEncode(payload),
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );

  Response _badRequest(String message) => Response(
    400,
    body: jsonEncode({'error': message}),
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );

  Response _unauthorized() => Response.unauthorized(
    jsonEncode({'error': 'Unauthorized'}),
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );

  Response _authError(String message) => Response.unauthorized(
    jsonEncode({'error': message}),
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );

  Response _notImplemented(String message) => Response(
    501,
    body: jsonEncode({'error': message}),
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );

  Future<Map<String, Object?>> _readJson(Request request) async {
    final body = await request.readAsString();
    if (body.isEmpty) return const <String, Object?>{};
    try {
      return Map<String, Object?>.from(
        jsonDecode(body) as Map<dynamic, dynamic>,
      );
    } on FormatException {
      return const <String, Object?>{};
    }
  }

  String? _extractBearer(Request request) {
    final auth = request.headers['authorization'];
    if (auth == null || !auth.startsWith('Bearer ')) return null;
    return auth.substring('Bearer '.length);
  }

  Future<AuthUser?> _requireAuth(Request request) async {
    final token = _extractBearer(request);
    if (token == null) return null;
    try {
      final claims = authService.verifyToken(token);
      if (claims['typ'] != 'access') return null;
      final userId = claims['sub'] as String?;
      if (userId == null) return null;
      return await authService.userStore.findById(userId);
    } on JWTException {
      return null;
    }
  }

  Map<String, Object?> _userPayload(AuthUser user) => <String, Object?>{
    'id': user.id,
    'email': user.email,
    if (user.firstName != null) 'firstName': user.firstName,
    if (user.lastName != null) 'lastName': user.lastName,
    if (user.phoneNumber != null) 'phoneNumber': user.phoneNumber,
    'providers': user.providers,
    'roles': user.roles,
    'isActive': user.isActive,
    'emailVerified': user.emailVerified,
    'totpEnabled': user.totpEnabled,
    'tenantId': user.tenantId,
    'createdAt': user.createdAt?.toIso8601String(),
    'updatedAt': user.updatedAt?.toIso8601String(),
  };

  List<String> _stringList(Object? value) =>
      (value as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false);

  Map<String, Object?> _adminUserPayload(AuthUser user) => <String, Object?>{
    'id': user.id,
    'email': user.email,
    'role': user.roles.isEmpty ? null : user.roles.first,
    'roles': user.roles,
    'isEmailVerified': user.emailVerified,
    'isTotpEnabled': user.totpEnabled,
    'createdAt': user.createdAt?.toIso8601String(),
  };

  int _parseLimit(Request request) {
    final value = int.tryParse(request.url.queryParameters['limit'] ?? '');
    return (value ?? 20).clamp(1, 100);
  }

  int _parseOffset(Request request) {
    final value = int.tryParse(request.url.queryParameters['offset'] ?? '');
    return max(0, value ?? 0);
  }

  String _buildAdminUiHtml() {
    final adminConfig = <String, Object?>{
      'base': config.adminUiPath,
      'featSessions': authService.sessionStore is AdminSessionStore,
      'featRoles': true,
      'featTenants': tenantStore != null,
      'featMetadata': true,
      'feat2faPolicy': false,
      'featControl': true,
      'featLinkedAccounts': true,
      'featApiKeys': true,
      'featWebhooks': false,
      'featTemplates': true,
      'featUpload': false,
      'uploadBaseUrl': '',
      'sessionBased': false,
      'authApiPrefix': config.apiBasePath,
    };
    return embeddedAdminUi.replaceFirst(
      RegExp(r'window\.__ADMIN_CONFIG__ = \{.*?\};', dotAll: true),
      'window.__ADMIN_CONFIG__ = ${jsonEncode(adminConfig)};',
    );
  }

  /// The document served at `GET <apiBasePath>/ui/config`.
  ///
  /// It has the shape of awesome-node-auth's (`ui.router.ts`, `getUiConfig`
  /// plus `headless`), in the same key order, and with nothing configured it
  /// is byte-for-byte what node serves with nothing configured.
  /// [AuthConfig.uiConfig] is merged over it.
  Map<String, Object?> _buildUiConfig(Request request) {
    final queryLang = request.url.queryParameters['lang'];
    final document = <String, Object?>{
      'apiPrefix': config.apiBasePath,
      // A flag unhides a link or button on the login page. Only google and
      // github are derived from the wiring: their buttons lead to
      // <apiBasePath>/oauth/<provider>, which this router serves. The others
      // stay false, node's answer when nothing is configured, because the
      // pages they link to (register, forgot-password, ...) are not embedded
      // here and would answer 404. Set them through uiConfig.
      'features': <String, Object?>{
        'register': false,
        'magicLink': false,
        'sms': false,
        'google': _oauthOffered('google'),
        'github': _oauthOffered('github'),
        'forgotPassword': false,
        'verifyEmail': false,
        'twoFactor': false,
      },
      // node's branding defaults. The clients render siteName as the page
      // heading, so they are wire values, not a claim about the server.
      'ui': <String, Object?>{
        'primaryColor': '#4a90d9',
        'secondaryColor': '#6c757d',
        'siteName': 'Awesome Node Auth',
      },
      'translations': <String, Object?>{},
      'lang': queryLang == null || queryLang.isEmpty
          ? config.defaultLocale
          : queryLang,
      // node's headless mode: auth.js is served, the pages are not, and
      // auth.js must not redirect to a login page that answers 404.
      'headless': !config.enableAuthUi,
    };
    for (final MapEntry(:key, :value) in config.uiConfig.entries) {
      final current = document[key];
      if (current is Map<String, Object?> && value is Map) {
        document[key] = <String, Object?>{
          ...current,
          ...value.cast<String, Object?>(),
        };
      } else {
        document[key] = value;
      }
    }
    return document;
  }

  bool _oauthOffered(String provider) =>
      callbacks.onOAuthStart != null &&
      config.oauthProviders.contains(provider);

  String _sixDigitOtp() {
    final n = Random.secure().nextInt(1000000);
    return n.toString().padLeft(6, '0');
  }

  bool _isUsableToken(TokenRecord? record, {required String purpose}) {
    if (record == null) return false;
    if (record.purpose != purpose) return false;
    if (record.isConsumed) return false;
    if (record.isExpiredAt(DateTime.now().toUtc())) return false;
    return true;
  }
}
