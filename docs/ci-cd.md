# CI/CD Documentation

This repository uses GitHub Actions for continuous integration and delivery.

## Shared toolchain setup

Every workflow installs Flutter through the composite action at
`.github/actions/setup-flutter`, which pins the SDK version (currently
**3.41.1**), restores the pub cache, and runs `flutter pub get`.

Pinning matters: `channel: stable` floats, so a new Flutter release can change
the formatter or the lint set and turn CI red with no change to this repo. To
move to a new Flutter version, bump the `flutter-version` default in that
action and the prerequisites table in the README in the same PR — the ensuing
`dart format` churn then lands as a deliberate change.

All third-party actions are pinned to commit SHAs with the tag in a trailing
comment. Dependabot's `github-actions` ecosystem updates both.

## The Android toolchain is a matrix, not four independent knobs

Flutter, the Android Gradle Plugin, Gradle, and Kotlin have to move together.
Dependabot does not know that, and twice it opened major bumps that were merged
and left `main` unable to build an APK:

- **AGP 9** removes the `kotlin-android` plugin, requires Gradle 9.5+, and makes
  Flutter 3.41.1's own Gradle plugin throw an NPE while applying.
- **Gradle 9** breaks AGP 8.11.1, which cannot create its problem-reporter
  service during configuration.
- **Kotlin 2.4** removed the string-valued `android.kotlinOptions.jvmTarget`,
  which is a script compilation error until you move to `compilerOptions`.

Three things now hold the line:

1. `.github/dependabot.yml` ignores major bumps for `com.android.application`,
   `gradle`, and `gradle-wrapper`.
2. `test/toolchain_test.dart` asserts the matrix in the *fast* test job — AGP
   major, Gradle major, Kotlin major, the absence of the removed `jvmTarget`
   DSL, SHA-pinning of every third-party action, and the absence of a
   `secrets`-gated step-level `if:`. Each failure says what breaks and what to
   do about it.
3. The Android job runs `:app:signingReport` before the APK build, so an
   incompatible combination fails at configuration instead of minutes in.

To migrate deliberately: bump Flutter first, then AGP and Gradle together, then
relax the expectations in `test/toolchain_test.dart` and the ignore rules in
`.github/dependabot.yml` in the same change.

Note there is no `bundler` entry for `/ios` — there is no Gemfile, so it failed
on every run with "No files found in /ios". iOS dependencies come from
CocoaPods, which Dependabot does not support.

## Workflows

### 1) CI — `.github/workflows/ci.yml`

Triggers: pull requests, push to `main`, manual dispatch.

| Job | Runner | What it does |
|-----|--------|--------------|
| `analyze-and-test` | ubuntu | Version metadata check, `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test --coverage`, coverage floor, uploads `coverage-lcov` |
| `lint-workflows` | ubuntu | actionlint over `.github/workflows` |
| `build-web` | ubuntu | `flutter build web --release` |
| `build-android` | ubuntu | Release APK and App Bundle |
| `build-ios` | macOS | Unsigned iOS release build |

`build-ios` is skipped on pull requests unless the PR carries the `ios` label
(applied automatically when `ios/**` changes), because macOS runner minutes
bill at 10× the Linux rate. It always runs on `main` and via manual dispatch.

#### Coverage floor

`tool/check_coverage.dart` parses `coverage/lcov.info`, prints per-file line
coverage worst-first, writes a one-line verdict to the job summary, and exits
non-zero below the floor declared at the top of that file. Generated files
(`lib/firebase_options.dart`) and dev-only entrypoints (`lib/dev/`) are
excluded. Raise the floor as coverage improves; never lower it to turn a build
green.

Run it locally with `make coverage-check`.

### 2) Deploy Web — `.github/workflows/deploy_web.yml`

Triggers: push to `main`, manual dispatch.

Builds with `--base-href "/<repo-name>/"`, copies `index.html` to `404.html` so
deep links survive a refresh, and deploys to GitHub Pages. Only the `deploy`
job holds the `pages: write` and `id-token: write` scopes.

### 3) Release Packaging — `.github/workflows/release.yml`

Triggers: git tags beginning with `v`.

Outputs the Android APK and App Bundle, a Web tarball, an unsigned iOS app
bundle zip, and `SHA256SUMS.txt`, published to GitHub Releases with generated
notes. Only the final `publish` job has `contents: write`.

Android signing activates when `ANDROID_KEYSTORE_BASE64` is set; the run's job
summary states whether the artifacts came out signed or unsigned. The check
lives in a job-level `env:` because the `secrets` context is **not** available
to step-level `if:` conditions — a gate written as
`if: ${{ secrets.FOO != '' }}` silently evaluates false and the step never runs.

### 4) Dependency Review — `.github/workflows/dependency-review.yml`

Fails a PR that introduces a dependency with a high-or-worse known
vulnerability, or one under a denied licence.

### 5) Dependabot Auto-merge — `.github/workflows/dependabot-auto-merge.yml`

Enables auto-merge on Dependabot patch and minor PRs so they land once CI is
green. Major bumps wait for a human. Auto-merge only takes effect if branch
protection requires status checks — without it, the PR merges immediately.

### 6) Labeler — `.github/workflows/labeler.yml`

Applies path-based labels from `.github/labeler.yml`. The `ios` label it adds
is what opts a PR into the iOS build job.

### 7) Stale — `.github/workflows/stale.yml`

Weekly sweep marking issues and PRs stale after 60 quiet days and closing them
14 days later. `pinned`, `security`, and `roadmap` are exempt.

## Required repository settings

1. Settings → Pages → Source: **GitHub Actions**.
2. Protect `main`:
   - Require a pull request before merging.
   - Require status checks: `CI / Analyze & test`, `CI / Build web`,
     `CI / Build Android`, `CI / Lint workflows`,
     `Dependency Review / Review dependency changes`.
   - Require branches to be up to date before merging.
   - Optional: require review from code owners.
3. Settings → General → Pull Requests: **Allow auto-merge** (required by the
   Dependabot auto-merge workflow).
4. Create the labels used by `.github/labeler.yml`: `android`, `ios`, `web`,
   `courses`, `tests`, `documentation`, `ci`, `dependencies`. Labeler creates
   missing ones on first run, but pre-creating them gives you the colours.

## Release secrets

| Secret | Purpose |
|--------|---------|
| `ANDROID_KEYSTORE_BASE64` | Base64 of the upload keystore; absent means unsigned Android artifacts |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Signing key alias |
| `ANDROID_KEY_PASSWORD` | Signing key password |

## Local parity

`make ci` runs the same core loop: format check, analysis, tests with the
coverage floor, and the Web/Android release builds. `make build-ios-no-codesign`
covers the iOS job on macOS.

Packaging commands are documented in [docs/release.md](release.md).

## Troubleshooting

- **Formatting fails** — run `dart format lib test tool` and commit. If the diff
  is large and you did not touch those files, the pinned Flutter version was
  probably just bumped; land the reformat as its own commit.
- **Analysis fails** — run `flutter analyze` locally.
- **Coverage floor fails** — run `make coverage-check`; the worst-covered files
  are listed first.
- **Web deploy path issues** — verify the repository name against the base href.
- **Release version verification fails** — the pushed tag must match
  `make version-tag` exactly.
- **Dependabot PRs do not merge** — check that auto-merge is enabled in repo
  settings and that branch protection requires status checks.
