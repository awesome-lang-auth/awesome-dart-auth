## Unreleased

- `authUiPath` and `authJsPath` default to `<apiBasePath>/ui` and
  `<authUiPath>/auth.js`, so setting `apiBasePath` alone moves `auth.js`,
  `/ui/config`, `base.css` and the login page together. Explicit values still
  win, and `copyWith(apiBasePath: ...)` derives the paths again.
- `GET <apiBasePath>/ui/config` serves awesome-node-auth's document shape
  (`apiPrefix`, `features`, `ui`, `translations`, `lang`, `headless`) instead
  of `{}`. With nothing configured it is byte-identical to node's. `uiConfig`
  is merged into it, and `headless` is `true` when `enableAuthUi` is `false`.
- `auth.js` is still served whenever the router is mounted, including with
  `enableAuthUi: false`; a test pins its sha256 to awesome-node-auth 1.10.8.

## 1.9.0

- First release on pub.dev.
- Server-side authentication for Shelf and Dart Frog backends, ported from
  [awesome-node-auth](https://github.com/awesome-lang-auth/awesome-node-auth)
  and versioned with its 1.9.0 release.
- The repository [README](https://github.com/awesome-lang-auth/awesome-dart-auth#readme)
  has the parity table against the reference server.
