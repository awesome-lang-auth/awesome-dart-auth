import 'package:meta/meta.dart';

/// Controls when session revocation is checked for stateful sessions.
enum SessionCheckOn {
  /// Check on every authenticated API call.
  allCalls,

  /// Check only when a refresh token is exchanged.
  refresh,

  /// Never check (stateless mode).
  none,
}

/// Immutable configuration for the awesome-dart-auth server runtime.
@immutable
class AuthConfig {
  /// Creates a validated authentication configuration.
  AuthConfig({
    required this.jwtSecret,
    required this.issuer,
    this.audience = const {'awesome-dart-auth-clients'},
    this.accessTokenTtl = const Duration(minutes: 15),
    this.refreshTokenTtl = const Duration(days: 30),
    this.adminUiPath = '/auth/admin',
    this.authUiPath = '/auth/ui',
    this.authJsPath = '/auth/ui/auth.js',
    this.openApiPath = '/auth/openapi.json',
    this.discoveryPath = '/auth/.well-known/openid-configuration',
    this.authorizationPath = '/auth/authorize',
    this.tokenPath = '/auth/token',
    this.userInfoPath = '/auth/userinfo',
    this.jwksPath = '/auth/jwks',
    this.apiBasePath = '/auth',
    this.defaultLocale = 'en',
    this.supportedLocales = const {'en', 'it'},
    this.enableAdminUi = true,
    this.enableAuthUi = true,
    this.enableIdpMode = true,
    this.enableTelemetry = true,
    this.enableSse = true,
    this.enableMcpCompatibility = true,
    this.allowCookieTokens = true,
    this.allowBearerTokens = true,
    this.oauthProviders = const {'google', 'github', 'generic'},
    this.sessionCheckOn = SessionCheckOn.refresh,
    this.cookieSecure = true,
    this.cookieSameSite = 'lax',
    this.cookiePrefix,
    this.uiConfig = const <String, Object?>{},
    this.issueSessionOnRegister = false,
  }) {
    _validate();
  }

  /// Creates a local development configuration.
  AuthConfig.development({
    required String jwtSecret,
    String issuer = 'http://localhost:8080',
  }) : this(
         jwtSecret: jwtSecret,
         issuer: issuer,
         cookieSecure: false,
       );

  /// Creates a test-friendly configuration with short token lifetimes.
  AuthConfig.testing({
    required String jwtSecret,
    String issuer = 'http://localhost:test',
  }) : this(
         jwtSecret: jwtSecret,
         issuer: issuer,
         accessTokenTtl: const Duration(minutes: 5),
         refreshTokenTtl: const Duration(hours: 1),
         cookieSecure: false,
       );

  /// Creates a production-oriented configuration.
  AuthConfig.production({
    required String jwtSecret,
    required String issuer,
    Set<String> audience = const {'awesome-dart-auth-clients'},
  }) : this(
         jwtSecret: jwtSecret,
         issuer: issuer,
         audience: audience,
       );

  /// Shared HMAC/JWT secret.
  final String jwtSecret;

  /// Issuer value embedded in tokens and discovery metadata.
  final String issuer;

  /// Allowed audiences for generated tokens.
  final Set<String> audience;

  /// Access token lifetime.
  final Duration accessTokenTtl;

  /// Refresh token lifetime.
  final Duration refreshTokenTtl;

  /// Path that serves the embedded admin UI.
  final String adminUiPath;

  /// Path that serves the embedded auth UI.
  final String authUiPath;

  /// Path that serves the embedded browser SDK.
  final String authJsPath;

  /// Path that serves the generated OpenAPI specification.
  final String openApiPath;

  /// OIDC discovery endpoint path.
  final String discoveryPath;

  /// OIDC authorization endpoint path.
  final String authorizationPath;

  /// Token endpoint path.
  final String tokenPath;

  /// UserInfo endpoint path.
  final String userInfoPath;

  /// JWKS endpoint path.
  final String jwksPath;

  /// Base path for the auth surface.
  final String apiBasePath;

  /// Built-in locale used when the requested locale is unavailable.
  final String defaultLocale;

  /// Supported mail template locales.
  final Set<String> supportedLocales;

  /// Whether the admin UI should be exposed.
  final bool enableAdminUi;

  /// Whether the auth UI should be exposed.
  final bool enableAuthUi;

  /// Whether OIDC Identity Provider routes should be exposed.
  final bool enableIdpMode;

  /// Whether auth events should be persisted to telemetry.
  final bool enableTelemetry;

  /// Whether SSE features are enabled.
  final bool enableSse;

  /// Whether MCP compatibility helpers should be enabled.
  final bool enableMcpCompatibility;

  /// Whether cookie-based authentication is enabled.
  final bool allowCookieTokens;

  /// Whether bearer-token authentication is enabled.
  final bool allowBearerTokens;

  /// Registered OAuth providers.
  final Set<String> oauthProviders;

  /// Controls when stateful session revocation is checked.
  final SessionCheckOn sessionCheckOn;

  /// Whether to set the `Secure` flag on auth cookies.
  final bool cookieSecure;

  /// SameSite attribute for auth cookies (`lax`, `strict`, or `none`).
  final String cookieSameSite;

  /// Optional cookie name prefix (`__Host-` or `__Secure-`).
  final String? cookiePrefix;

  /// Static configuration map surfaced by the `GET /auth/ui/config` endpoint.
  final Map<String, Object?> uiConfig;

  /// Whether `POST /register` also opens a session for the new account.
  ///
  /// Off (the default, the family reference's behaviour): register answers
  /// `201 {"success": true, "userId": "<id>"}` and issues nothing; the client
  /// calls `POST /login` afterwards. On: the same `201` body plus the
  /// `accessToken` / `refreshToken` fields a successful login returns, with
  /// the refresh session created the way login creates it. Nothing is issued
  /// when the registration is refused, or when the email-verification policy
  /// is `strict`.
  final bool issueSessionOnRegister;

  /// Returns a copy of this configuration with updated fields.
  AuthConfig copyWith({
    String? jwtSecret,
    String? issuer,
    Set<String>? audience,
    Duration? accessTokenTtl,
    Duration? refreshTokenTtl,
    String? adminUiPath,
    String? authUiPath,
    String? authJsPath,
    String? openApiPath,
    String? discoveryPath,
    String? authorizationPath,
    String? tokenPath,
    String? userInfoPath,
    String? jwksPath,
    String? apiBasePath,
    String? defaultLocale,
    Set<String>? supportedLocales,
    bool? enableAdminUi,
    bool? enableAuthUi,
    bool? enableIdpMode,
    bool? enableTelemetry,
    bool? enableSse,
    bool? enableMcpCompatibility,
    bool? allowCookieTokens,
    bool? allowBearerTokens,
    Set<String>? oauthProviders,
    SessionCheckOn? sessionCheckOn,
    bool? cookieSecure,
    String? cookieSameSite,
    Object? cookiePrefix = _sentinel,
    Map<String, Object?>? uiConfig,
    bool? issueSessionOnRegister,
  }) {
    return AuthConfig(
      jwtSecret: jwtSecret ?? this.jwtSecret,
      issuer: issuer ?? this.issuer,
      audience: audience ?? this.audience,
      accessTokenTtl: accessTokenTtl ?? this.accessTokenTtl,
      refreshTokenTtl: refreshTokenTtl ?? this.refreshTokenTtl,
      adminUiPath: adminUiPath ?? this.adminUiPath,
      authUiPath: authUiPath ?? this.authUiPath,
      authJsPath: authJsPath ?? this.authJsPath,
      openApiPath: openApiPath ?? this.openApiPath,
      discoveryPath: discoveryPath ?? this.discoveryPath,
      authorizationPath: authorizationPath ?? this.authorizationPath,
      tokenPath: tokenPath ?? this.tokenPath,
      userInfoPath: userInfoPath ?? this.userInfoPath,
      jwksPath: jwksPath ?? this.jwksPath,
      apiBasePath: apiBasePath ?? this.apiBasePath,
      defaultLocale: defaultLocale ?? this.defaultLocale,
      supportedLocales: supportedLocales ?? this.supportedLocales,
      enableAdminUi: enableAdminUi ?? this.enableAdminUi,
      enableAuthUi: enableAuthUi ?? this.enableAuthUi,
      enableIdpMode: enableIdpMode ?? this.enableIdpMode,
      enableTelemetry: enableTelemetry ?? this.enableTelemetry,
      enableSse: enableSse ?? this.enableSse,
      enableMcpCompatibility:
          enableMcpCompatibility ?? this.enableMcpCompatibility,
      allowCookieTokens: allowCookieTokens ?? this.allowCookieTokens,
      allowBearerTokens: allowBearerTokens ?? this.allowBearerTokens,
      oauthProviders: oauthProviders ?? this.oauthProviders,
      sessionCheckOn: sessionCheckOn ?? this.sessionCheckOn,
      cookieSecure: cookieSecure ?? this.cookieSecure,
      cookieSameSite: cookieSameSite ?? this.cookieSameSite,
      cookiePrefix: identical(cookiePrefix, _sentinel)
          ? this.cookiePrefix
          : cookiePrefix as String?,
      uiConfig: uiConfig ?? this.uiConfig,
      issueSessionOnRegister:
          issueSessionOnRegister ?? this.issueSessionOnRegister,
    );
  }

  void _validate() {
    if (jwtSecret.trim().isEmpty) {
      throw ArgumentError.value(jwtSecret, 'jwtSecret', 'must not be empty');
    }
    if (issuer.trim().isEmpty) {
      throw ArgumentError.value(issuer, 'issuer', 'must not be empty');
    }
    if (accessTokenTtl <= Duration.zero) {
      throw ArgumentError.value(
        accessTokenTtl,
        'accessTokenTtl',
        'must be positive',
      );
    }
    if (refreshTokenTtl <= Duration.zero) {
      throw ArgumentError.value(
        refreshTokenTtl,
        'refreshTokenTtl',
        'must be positive',
      );
    }
    if (!allowBearerTokens && !allowCookieTokens) {
      throw ArgumentError(
        'At least one transport between cookies and bearer tokens must be '
        'enabled.',
      );
    }
    if (!supportedLocales.contains(defaultLocale)) {
      throw ArgumentError.value(
        defaultLocale,
        'defaultLocale',
        'must be present in supportedLocales',
      );
    }
  }
}

const Object _sentinel = Object();
