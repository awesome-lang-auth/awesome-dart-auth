import 'package:awesome_dart_auth/src/config/auth_config.dart';

/// Generates an OpenAPI document for the built-in auth routes.
Map<String, Object?> buildOpenApiDocument(AuthConfig config) => {
  'openapi': '3.1.0',
  'info': {
    'title': 'awesome-dart-auth',
    'version': '0.1.0',
    'description':
        'Server-side authentication API compatible with ng-awesome-node-auth '
        '(Angular) and awesome-node-auth-flutter (Flutter).',
  },
  'paths': {
    // ── UI assets ────────────────────────────────────────────────────────
    config.adminUiPath: {
      'get': {'summary': 'Serve the embedded admin UI'},
    },
    '${config.adminUiPath}/assets/admin.js': {
      'get': {'summary': 'Serve the embedded admin runtime'},
    },
    '${config.adminUiPath}/assets/admin.css': {
      'get': {'summary': 'Serve the embedded admin stylesheet'},
    },
    config.authUiPath: {
      'get': {'summary': 'Redirect to the embedded auth login page'},
    },
    '${config.authUiPath}/login': {
      'get': {'summary': 'Serve the embedded auth login UI'},
    },
    config.authJsPath: {
      'get': {'summary': 'Serve the embedded browser SDK'},
    },
    '${config.apiBasePath}/ui/base.css': {
      'get': {'summary': 'Serve the embedded auth stylesheet'},
    },
    '${config.apiBasePath}/ui/config': {
      'get': {'summary': 'Return the UI configuration document'},
    },
    // ── OIDC / JWKS ───────────────────────────────────────────────────────
    if (config.enableIdpMode) ...{
      config.discoveryPath: {
        'get': {'summary': 'Serve the OIDC discovery document'},
      },
      config.jwksPath: {
        'get': {'summary': 'Serve the JSON Web Key Set'},
      },
      config.userInfoPath: {
        'get': {'summary': 'Return user info based on the bearer token'},
      },
      config.tokenPath: {
        'post': {'summary': 'Issue a demo access + refresh token pair'},
      },
    },
    // ── Session ───────────────────────────────────────────────────────────
    '${config.apiBasePath}/register': {
      'post': {'summary': 'Create a new account'},
    },
    '${config.apiBasePath}/login': {
      'post': {'summary': 'Login with email + password'},
    },
    '${config.apiBasePath}/logout': {
      'post': {'summary': 'Logout and revoke the current session'},
    },
    '${config.apiBasePath}/me': {
      'get': {'summary': 'Return the current authenticated user'},
    },
    '${config.apiBasePath}/refresh': {
      'post': {'summary': 'Refresh the access token'},
    },
    // ── Account management ────────────────────────────────────────────────
    '${config.apiBasePath}/profile': {
      'patch': {'summary': 'Update first / last name'},
    },
    '${config.apiBasePath}/account': {
      'delete': {'summary': 'Delete the current account'},
    },
    '${config.apiBasePath}/forgot-password': {
      'post': {'summary': 'Initiate password recovery'},
    },
    '${config.apiBasePath}/reset-password': {
      'post': {'summary': 'Reset password with token'},
    },
    '${config.apiBasePath}/change-password': {
      'post': {'summary': 'Change password (authenticated)'},
    },
    '${config.apiBasePath}/send-verification-email': {
      'post': {'summary': 'Resend email verification'},
    },
    '${config.apiBasePath}/verify-email': {
      'get': {'summary': 'Verify email address'},
    },
    '${config.apiBasePath}/change-email/request': {
      'post': {'summary': 'Request email address change'},
    },
    '${config.apiBasePath}/change-email/confirm': {
      'post': {'summary': 'Confirm email address change'},
    },
    // ── TOTP / 2FA ────────────────────────────────────────────────────────
    '${config.apiBasePath}/2fa/setup': {
      'post': {'summary': 'Begin TOTP setup (returns QR code + secret)'},
    },
    '${config.apiBasePath}/2fa/verify-setup': {
      'post': {'summary': 'Confirm TOTP setup'},
    },
    '${config.apiBasePath}/2fa/verify': {
      'post': {'summary': 'Verify TOTP code during login'},
    },
    '${config.apiBasePath}/2fa/disable': {
      'post': {'summary': 'Disable TOTP'},
    },
    // ── Magic link ────────────────────────────────────────────────────────
    '${config.apiBasePath}/magic-link/send': {
      'post': {'summary': 'Send a magic-link email'},
    },
    '${config.apiBasePath}/magic-link/verify': {
      'post': {'summary': 'Verify magic-link token'},
    },
    // ── SMS OTP ───────────────────────────────────────────────────────────
    '${config.apiBasePath}/sms/send': {
      'post': {'summary': 'Send an SMS OTP'},
    },
    '${config.apiBasePath}/sms/verify': {
      'post': {'summary': 'Verify SMS OTP'},
    },
    '${config.apiBasePath}/add-phone': {
      'post': {'summary': 'Add phone number to account'},
    },
    // ── Sessions (device management) ──────────────────────────────────────
    '${config.apiBasePath}/sessions': {
      'get': {'summary': 'List all active sessions'},
    },
    '${config.apiBasePath}/sessions/{handle}': {
      'delete': {'summary': 'Revoke a session'},
    },
    // ── OAuth ─────────────────────────────────────────────────────────────
    '${config.apiBasePath}/oauth/{provider}': {
      'get': {'summary': 'Start provider OAuth flow'},
    },
    '${config.apiBasePath}/oauth/{provider}/callback': {
      'get': {'summary': 'Complete provider callback and create session'},
    },
    // ── Account linking ───────────────────────────────────────────────────
    '${config.apiBasePath}/link-request': {
      'post': {'summary': 'Initiate account linking'},
    },
    '${config.apiBasePath}/link-verify': {
      'post': {'summary': 'Verify linking token'},
    },
    '${config.apiBasePath}/linked-accounts': {
      'get': {'summary': 'List linked OAuth providers'},
    },
    '${config.apiBasePath}/linked-accounts/{provider}/{id}': {
      'delete': {'summary': 'Unlink a provider'},
    },
  },
};
