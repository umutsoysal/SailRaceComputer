# CI/CD Documentation

This repository uses GitHub Actions for continuous integration and delivery.

## Workflows

## 1) CI

- File: `.github/workflows/ci.yml`
- Triggers: push to `main`, pull requests
- Checks:
  - `flutter pub get`
  - `dart format --set-exit-if-changed`
  - `flutter analyze`
  - `flutter test --coverage`
- Artifact:
  - `coverage/lcov.info` uploaded as `coverage-lcov`

## 2) Deploy Web

- File: `.github/workflows/deploy_web.yml`
- Triggers: push to `main`, manual dispatch
- Build command:
  - `flutter build web --release --base-href "/<repo-name>/"`
- Deploy target:
  - GitHub Pages via `actions/deploy-pages`

## Required repository settings

1. In GitHub repository settings, enable GitHub Pages with source set to GitHub Actions.
2. Protect `main` branch:
   - Require pull request before merging.
   - Require status checks to pass (`CI / analyze-and-test`).
3. Keep dependency update PRs enabled via Dependabot.

## Recommended branch protection checks

- `CI / analyze-and-test`
- Require up-to-date branches before merge
- Optional: require review from code owners

## Dependency automation

Dependabot configuration is in `.github/dependabot.yml` and updates:

- Dart/Flutter dependencies (`pub`)
- GitHub Actions
- Android Gradle dependencies
- iOS bundler dependencies

## Troubleshooting

- CI fails on formatting:
  - Run `dart format lib test` and commit changes.
- CI fails on analysis:
  - Run `flutter analyze` locally and resolve warnings/errors.
- Web deploy path issues:
  - Verify repository name and check the base href in the deploy workflow.
