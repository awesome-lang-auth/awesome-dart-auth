# Contributing to awesome-dart-auth

Thank you for your interest in contributing! This guide explains how to get started.

## Development setup

```bash
git clone https://github.com/awesome-lang-auth/awesome-dart-auth
cd awesome-dart-auth
dart pub get
dart run melos bootstrap
dart run melos exec --fail-fast -- dart analyze .
dart run melos exec --fail-fast --dir-exists=test -- dart test
```

## Project structure

```
packages/   Core package and framework adapters
examples/   Integration examples
```

Every package and example is a member of the pub workspace declared in the root `pubspec.yaml`. A new one must be added to its `workspace:` list and declare `resolution: workspace` in its own `pubspec.yaml`; CI fails when melos does not see every `pubspec.yaml` under `packages/` and `examples/`.

## How to contribute

1. **Fork** the repository and create a branch from `main`.
2. Make your changes following the style guide below.
3. Add or update tests to cover your change.
4. Run `dart run melos exec --fail-fast -- dart analyze .` and `dart run melos exec --fail-fast --dir-exists=test -- dart test` — all checks must pass.
5. Open a **Pull Request** against `main`.

## Style guide

- Dart SDK 3.11+.
- No new runtime dependencies without discussion in an issue first.
- Existing tests must not be removed or weakened.
- Each commit should be a single logical change.

## Reporting bugs & requesting features

Use the [issue templates](.github/ISSUE_TEMPLATE/) provided. Search for existing issues before opening a new one.

## Security issues

Do **not** open public issues for security vulnerabilities. See [SECURITY.md](SECURITY.md) for the responsible disclosure process.

## Code of Conduct

All contributors are expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

By contributing you agree that your work will be licensed under the [MIT License](LICENSE) that covers this project.
