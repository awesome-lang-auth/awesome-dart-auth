# awesome-dart-auth

[![Dart](https://img.shields.io/badge/dart-3.11+-blue.svg)](https://dart.dev)
[![Shelf](https://img.shields.io/badge/Shelf-1.4+-green.svg)](https://pub.dev/packages/shelf)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Server-side authentication library for Dart backends** (Shelf / Dart Frog) that replicates the [awesome-node-auth](https://github.com/awesome-lang-auth/awesome-node-auth) Node.js backend in Dart.

> **Important:** `awesome-dart-auth` is a server-side package.  
> Flutter client support continues through the existing [`awesome_flutter_auth`](https://github.com/awesome-lang-auth/awesome-flutter-auth) client package.

Fully compatible with:
- **[@awesome-lang-auth/angular](https://github.com/awesome-lang-auth/awesome-angular-auth)** — Angular client library
- **[awesome_flutter_auth](https://github.com/awesome-lang-auth/awesome-flutter-auth)** — Flutter/Dart client library

Supports **both authentication strategies** used by those clients:

| Platform | Strategy | Token |
|---|---|---|
| Angular / Web | Cookie (HttpOnly) + CSRF | `access-token` cookie + `X-CSRF-Token` header |
| Flutter Native (iOS/Android/Desktop) | Bearer token | `Authorization: Bearer <token>` + `X-Auth-Strategy: bearer` |

---

## Parity Snapshot vs `awesome-node-auth`

| Capability | Status in `awesome-dart-auth` | Notes |
|---|---|---|
| Auth strategies (email/password, magic link, SMS OTP, TOTP 2FA, OAuth linking) | ✅ Implemented | Dedicated endpoints for each strategy; OAuth uses `onOAuthStart` / `onOAuthCallback` hooks. |
| Token management (cookie/bearer, access/refresh rotation, secure cookies) | ✅ Implemented | Cookie + bearer mode, rotation, and optional `cookiePrefix` (`__Host-` / `__Secure-`) via `AuthConfig`. |
| Identity Provider (IdP) mode (RS256 + JWKS + resource server validation) | ✅ Implemented | OIDC discovery + JWKS endpoint exposed; `enableIdpMode` flag controls availability. |
| Stateful sessions | ✅ Implemented | Session lifecycle with revocation checks configurable via `AuthConfig.sessionCheckOn` (`allCalls` / `refresh` / `none`). |
| Dynamic email templates + UI i18n fallback | ✅ Implemented | `TemplateStore` contract + `TemplateRenderer` with built-in `en`/`it` templates ported from `MailerService` fallback content in `awesome-node-auth` (`password-reset`, `magic-link`, `welcome`, `verify-email`, `email-changed`, `invitation`). |
| CSRF protection | ✅ Implemented | `csrfMiddleware()` uses cookie + header double-submit validation for browser flows; bearer requests skip validation. |
| Account management | ✅ Implemented | Register, login, logout, me, profile update, password / email change, verification, and account deletion. |
| Account linking | ✅ Implemented | Link request/verify plus linked-account listing and unlinking via `AuthCallbacks`. |
| RBAC | ✅ Implemented | `RolesPermissionsStore` with role-enriched JWT claims. |
| Multi-tenancy | ✅ Implemented | `TenantStore` contract and `tenantId` propagation through models and tokens. |
| Admin panel | ✅ Implemented | Embedded admin UI + admin API routes are available under `/auth/admin` and `/auth/admin/api/*` (store-driven, with optional capabilities enabled based on configured stores). |
| Built-in UI + auth runtime (`auth.js`) | ✅ Implemented | Upstream login UI + `auth.js` + `base.css` assets are served at `/auth/ui/login`, `/auth/ui/auth.js`, `/auth/ui/base.css` (`/auth/ui` redirects to `/auth/ui/login`). |
| Client libraries compatibility (Angular + Flutter) | ✅ Implemented | Cookie+CSRF (web) and bearer (native) strategies are both supported. |
| Event-driven tooling (event bus, SSE, inbound/outbound webhooks, telemetry, notify channels) | ✅ Implemented | `AuthTools`, `AuthEventBus`, `SseDistributor`, webhook signing, outgoing webhook dispatch (`WebhookStore` + `WebhookSender`), and multi-channel `notify()`. |
| API keys (M2M) | ✅ Implemented | `ApiKeyStore` contract and `ApiKeyRecord` model available. |
| OpenAPI / Swagger docs | ✅ Implemented | `buildOpenApiDocument()` generates a full OpenAPI 3.1 spec for all auth routes. |
| MCP server (`awesome-node-auth-mcp-server`) | ➖ Out of scope | No Dart-side MCP server is bundled; `enableMcpCompatibility` reserves the flag. |

---

## Monorepo layout

```
packages/
  awesome_dart_auth/         — framework-agnostic core
  awesome_dart_auth_shelf/   — Shelf adapter
  awesome_dart_auth_dart_frog/ — Dart Frog adapter
examples/
  shelf_mongodb/             — Shelf integration example
  dart_frog_postgres/        — Dart Frog integration example
```

---

## Getting started

```bash
dart pub get
dart run melos bootstrap
dart run melos exec --fail-fast -- dart analyze .
dart run melos exec --fail-fast --dir-exists=test -- dart test
```

---

## Quick start

```dart
import 'package:awesome_dart_auth/awesome_dart_auth.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final config = AuthConfig.development(jwtSecret: 'your-secret-here');

  final router = AuthRouter(
    config: config,
    authService: AuthService(
      config: config,
      userStore: myUserStore,
      sessionStore: mySessionStore,
    ),
    // Optional: supply side-effect callbacks to enable full auth flows
    callbacks: AuthCallbacks(
      onForgotPassword: (user, token) async {
        await mailer.send(user.email, 'Reset your password', token);
      },
      onMagicLinkSend: (user, token) async {
        await mailer.send(user.email, 'Your magic link', token);
      },
      onMagicLinkVerify: (token, mode) async {
        return await tokenStore.verify(token); // returns userId or null
      },
    ),
  );

  // Add CSRF middleware for Angular web clients
  final handler = const Pipeline()
      .addMiddleware(csrfMiddleware(apiBasePath: '/auth'))
      .addHandler(router.handler);

  final server = await shelf_io.serve(handler, 'localhost', 8080);
  print('Listening on http://localhost:${server.port}');
}
```

---

## AuthConfig

```dart
final config = AuthConfig(
  jwtSecret: 'your-secret',          // JWT signing secret
  issuer: 'https://auth.example.com',
  accessTokenTtl: Duration(minutes: 15),
  refreshTokenTtl: Duration(days: 30),
  sessionCheckOn: SessionCheckOn.refresh, // allCalls | refresh | none
  cookieSecure: true,                // Set false for local HTTP
  cookieSameSite: 'lax',
  cookiePrefix: '__Host-',           // Optional: __Host- or __Secure-
  uiConfig: {'theme': 'dark'},       // Returned by GET /auth/ui/config
  enableIdpMode: true,               // Expose OIDC discovery, JWKS, userinfo, token
  oauthProviders: {'google', 'github'},
  issueSessionOnRegister: false,     // POST /register also opens a session (default off)
);
```

### Register and sessions (`issueSessionOnRegister`)

Whether `POST /register` also logs the new account in is the instance administrator's choice, the same option in every library of the awesome-lang-auth family.

- **Off (default, as the reference awesome-node-auth):** `201 {"success": true, "userId": "<id>"}`. No token and no session row; the client calls `POST /login` afterwards.
- **On:** the same `201` body plus the `accessToken`, `refreshToken`, `expiresInSeconds` and `tokenType` fields a successful `POST /login` returns, and the refresh session row is created the way login creates it (device info from `User-Agent`, `identity.session.created` event).
- A refused registration (`400`, a throwing `onRegister` hook) never issues anything. With the admin email-verification policy set to `strict` (`emailVerificationMode: 'strict'` or `requireEmailVerification: true`), an unverified account gets no session even with the option on. An account the login would challenge for TOTP gets no session either.

> Breaking change: before this option, `POST /register` always answered `200` with `user` and a token pair. To keep that session behaviour, set `issueSessionOnRegister: true` (the body is now the family's `201 {success, userId, ...tokens}`, without `user`).

---

## Custom stores

Implement the store contracts to connect to your database:

```dart
class PostgresUserStore implements UserStore {
  @override
  Future<AuthUser?> findByEmail(String email) async { /* … */ }

  @override
  Future<AuthUser?> findById(String id) async { /* … */ }

  @override
  Future<AuthUser> save(AuthUser user) async { /* … */ }

  @override
  Future<AuthUser> update(AuthUser user) async { /* … */ }

  @override
  Future<void> delete(String id) async { /* … */ }
}
```

---

## API Endpoints

All endpoints are mounted under `apiBasePath` (default: `/auth`).

### Session
| Method | Path | Description |
|---|---|---|
| `POST` | `/register` | Create a new account (`201 {success, userId}`; also opens a session when `issueSessionOnRegister` is on) |
| `POST` | `/login` | Login with email + password |
| `POST` | `/logout` | Logout and revoke the current session |
| `GET` | `/me` | Return the current authenticated user |
| `POST` | `/refresh` | Refresh the access token |
| `PATCH` | `/profile` | Update first / last name |
| `DELETE` | `/account` | Delete the current account |

### Password
| Method | Path | Description |
|---|---|---|
| `POST` | `/forgot-password` | Initiate password recovery |
| `POST` | `/reset-password` | Reset password with token |
| `POST` | `/change-password` | Change password (authenticated) |
| `POST` | `/send-verification-email` | Resend email verification |
| `GET` | `/verify-email` | Verify email address |
| `POST` | `/change-email/request` | Request email address change |
| `POST` | `/change-email/confirm` | Confirm email address change |

### Two-Factor Authentication (TOTP)
| Method | Path | Description |
|---|---|---|
| `POST` | `/2fa/setup` | Begin TOTP setup (returns QR code + secret) |
| `POST` | `/2fa/verify-setup` | Confirm TOTP setup |
| `POST` | `/2fa/verify` | Verify TOTP code during login |
| `POST` | `/2fa/disable` | Disable TOTP |

### Magic Link
| Method | Path | Description |
|---|---|---|
| `POST` | `/magic-link/send` | Send a magic-link email |
| `POST` | `/magic-link/verify` | Verify magic-link token |

### SMS / OTP
| Method | Path | Description |
|---|---|---|
| `POST` | `/sms/send` | Send an SMS OTP |
| `POST` | `/sms/verify` | Verify SMS OTP |
| `POST` | `/add-phone` | Add phone number to account |

### Sessions (device management)
| Method | Path | Description |
|---|---|---|
| `GET` | `/sessions` | List all active sessions |
| `DELETE` | `/sessions/{handle}` | Revoke a session |

### OAuth
| Method | Path | Description |
|---|---|---|
| `GET` | `/oauth/{provider}` | Start provider OAuth flow (redirect via `onOAuthStart`) |
| `GET` | `/oauth/{provider}/callback` | Complete provider callback and create session |

### Account Linking
| Method | Path | Description |
|---|---|---|
| `POST` | `/link-request` | Initiate account linking |
| `POST` | `/link-verify` | Verify linking token |
| `GET` | `/linked-accounts` | List linked OAuth providers |
| `DELETE` | `/linked-accounts/{provider}/{id}` | Unlink a provider |

### Utilities / UI
| Method | Path | Description |
|---|---|---|
| `GET` | `/ui/config` | UI configuration (theme, branding) |
| `GET` | `/ui` | Redirects to `/ui/login` |
| `GET` | `/ui/login` | Embedded upstream login UI |
| `GET` | `/ui/base.css` | Embedded upstream auth stylesheet |
| `GET` | `/ui/auth.js` | Embedded browser SDK |
| `GET` | `/admin` | Embedded admin UI |
| `GET` | `/admin/assets/admin.css` | Embedded admin stylesheet |
| `GET` | `/admin/assets/admin.js` | Embedded admin runtime |
| `GET` | `/openapi.json` | OpenAPI 3.1 specification |

---

## Hooks / Callbacks

Plug in side-effects without subclassing by supplying `AuthCallbacks`:

```dart
final router = AuthRouter(
  config: config,
  authService: service,
  callbacks: AuthCallbacks(
    onRegister: (user) async {
      await sendWelcomeEmail(user.email);
      return user;
    },
    onForgotPassword: (user, token) async {
      final link = 'https://myapp.com/reset-password?token=$token';
      await mailer.send(user.email, 'Reset your password', link);
    },
    onMagicLinkSend: (user, token) async {
      await mailer.send(user.email, 'Your magic link', token);
    },
    onMagicLinkVerify: (token, mode) async {
      return await magicLinkStore.verify(token); // userId or null
    },
    onSmsSend: (user, otp) async {
      await smsClient.send(user.phoneNumber!, 'Your OTP: $otp');
    },
    onSmsVerify: (user, code) async {
      return await otpStore.verify(user.id, code);
    },
    onOAuthStart: (provider, redirectUri) async {
      return oauthClient.authorizationUrl(provider, redirectUri);
    },
    onOAuthCallback: (provider, code, redirectUri) async {
      return await oauthClient.handleCallback(provider, code, redirectUri);
    },
  ),
);
```

---

## CSRF Middleware

Required when Angular web clients are used:

```dart
final handler = const Pipeline()
    .addMiddleware(
      csrfMiddleware(
        apiBasePath: '/auth',
        cookieSecure: true,      // false for local HTTP development
        cookieSameSite: 'lax',
      ),
    )
    .addHandler(router.handler);
```

The middleware:
1. Sets a `csrf-token` cookie (readable by JavaScript) on every response.
2. Validates the `X-CSRF-Token` request header for mutating requests.
3. Automatically skips validation for login/register endpoints and bearer-token requests.

---

## AuthTools — multi-channel `notify()`

```dart
final tools = AuthTools(
  sse: mySseDistributor,
  notificationService: NotificationService(
    email: MailerConfig(
      endpoint: 'https://mailer.example.com/send',
      apiKey: 'mailer-key',
      fromAddress: 'no-reply@example.com',
    ),
    sms: SmsConfig(
      endpoint: 'https://sms.example.com/send',
      apiKey: 'sms-key',
    ),
  ),
  userStore: myUserStore,
  eventBus: myBus,
);

// SSE only (default)
await tools.notify('user:123', type: 'ping', data: {'msg': 'Hello!'});

// Email + SSE
await tools.notify(
  'user:123',
  type: 'subscription_expiring',
  data: {'days': 3},
  userId: '123',
  channels: [NotifyChannel.sse, NotifyChannel.email],
  emailSubject: 'Your subscription expires soon',
);

// Track a domain event
await tools.track('identity.auth.login.success', userId: 'user-123');
```

---

## AuthEventBus

```dart
final bus = InMemoryAuthEventBus();

// Subscribe
bus.subscribe().listen((event) {
  print('Event: ${event.type} for user ${event.userId}');
});

// Publish
await bus.publish(AuthEvent(
  type: 'identity.auth.login.success',
  occurredAt: DateTime.now().toUtc(),
  userId: 'user-123',
));
```

Standard event types emitted by `AuthService`:
- `identity.user.created`
- `identity.auth.login.success`
- `identity.auth.login.failed`
- `identity.session.created`
- `identity.session.revoked`

---

## Angular Integration

```typescript
// app.config.ts
import { provideAuth } from '@awesome-lang-auth/angular';

export const appConfig: ApplicationConfig = {
  providers: [
    provideAuth({ apiPrefix: '/auth' }),
  ]
};
```

---

## Flutter Integration

```dart
final auth = AuthClient(AuthOptions(
  apiPrefix: 'http://your-server/auth',
));
await auth.checkSession();
final result = await auth.login(LoginRequest(
  email: 'alice@example.com',
  password: 'secret123',
));
```

---

## Examples

See the example projects for end-to-end wiring:

- `examples/shelf_mongodb` — Shelf + MongoDB
- `examples/dart_frog_postgres` — Dart Frog + PostgreSQL
