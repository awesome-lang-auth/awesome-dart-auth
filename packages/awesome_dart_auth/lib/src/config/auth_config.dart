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
    String? authUiPath,
    String? authJsPath,
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
  }) : _authUiPath = authUiPath,
       _authJsPath = authJsPath {
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

  /// Path that serves the embedded auth UI pages.
  ///
  /// Defaults to `<apiBasePath>/ui`, so changing [apiBasePath] alone moves
  /// the pages, [authJsPath], `<apiBasePath>/ui/base.css` and
  /// `<apiBasePath>/ui/config` together, as awesome-node-auth does with its
  /// mount prefix.
  ///
  /// An explicit value is an escape hatch. The login page loads `base.css`
  /// and `auth.js` relative to itself, and `auth.js` takes the part of the
  /// page path before `/ui/` as the API prefix, so the built-in pages only
  /// work unchanged when this is `<apiBasePath>/ui`.
  String get authUiPath => _authUiPath ?? '$apiBasePath/ui';

  /// Path that serves the embedded browser SDK (`auth.js`).
  ///
  /// Defaults to `<authUiPath>/auth.js`, which is `<apiBasePath>/ui/auth.js`
  /// unless [authUiPath] is set explicitly. It is served whenever the router
  /// is mounted, even with [enableAuthUi] off.
  String get authJsPath => _authJsPath ?? '$authUiPath/auth.js';

  /// The [authUiPath] passed to the constructor, if any.
  final String? _authUiPath;

  /// The [authJsPath] passed to the constructor, if any.
  final String? _authJsPath;

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

  /// Base path for the auth surface (default `/auth`).
  ///
  /// The API routes, `<apiBasePath>/ui/config`, `<apiBasePath>/ui/base.css`
  /// and, unless they are set explicitly, [authUiPath] and [authJsPath] are
  /// all under it.
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

  /// Entries merged into the document served at `GET <apiBasePath>/ui/config`.
  ///
  /// The router always serves awesome-node-auth's document shape: `apiPrefix`,
  /// `features`, `ui`, `translations`, `lang` and `headless`. Each entry here
  /// replaces the top-level key of the same name, except that a map given for
  /// a key whose default is a map (`features`, `ui`, `translations`) is merged
  /// into it, so `{'ui': {'siteName': 'ACME'}}` keeps the default colors.
  /// Keys the reference does not know are added as they are. The default,
  /// an empty map, serves the document unchanged.
  final Map<String, Object?> uiConfig;

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
  }) {
    return AuthConfig(
      jwtSecret: jwtSecret ?? this.jwtSecret,
      issuer: issuer ?? this.issuer,
      audience: audience ?? this.audience,
      accessTokenTtl: accessTokenTtl ?? this.accessTokenTtl,
      refreshTokenTtl: refreshTokenTtl ?? this.refreshTokenTtl,
      adminUiPath: adminUiPath ?? this.adminUiPath,
      // The overrides, not the derived getters, so that a copy with a new
      // apiBasePath derives its UI paths from it again.
      authUiPath: authUiPath ?? _authUiPath,
      authJsPath: authJsPath ?? _authJsPath,
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
