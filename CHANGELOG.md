# Changelog

All notable changes to Race Mate are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
The public version lives in [`app_version.json`](app_version.json) and is
bumped with `make ship-patch` / `ship-minor` / `ship-major`; see
[docs/release.md](docs/release.md).

## [Unreleased]

### Added
- Screenshots in the README, captured from a real build driven by the boat
  simulator, plus [`lib/dev/screenshot_main.dart`](lib/dev/screenshot_main.dart)
  and [docs/screenshots.md](docs/screenshots.md) so they can be retaken.
- `tool/check_coverage.dart`: per-file coverage summary and an enforced
  line-coverage floor, wired into CI and `make coverage-check`.
- CI now builds iOS (on `main`, on demand, and on PRs labelled `ios`) and lints
  the workflow files with actionlint.
- Dependency review, Dependabot auto-merge for patch/minor updates, path-based
  PR labelling, and a stale-issue sweep.
- Tests for the course library, the imported-course picker, the help tour, the
  position-source error classifiers, and the geo math — 62 → 114 tests.

### Added
- **Package APK workflow** (`.github/workflows/package_apk.yml`) — an on-demand
  builder for install-ready Android APKs, so a build can reach a tester without
  cutting a release. It splits per ABI, which takes the download from ~50MB to
  ~18MB, names the files with version + build counter + commit, ships
  `SHA256SUMS.txt`, and writes a summary table of sizes and target devices. An
  opt-in `publish` input attaches them to a rolling `latest-build` prerelease so
  testers have one stable URL. Tagged releases now include the per-ABI APKs too.
- `test/toolchain_test.dart` — a fast sanity check over the build toolchain.
  Every assertion in it corresponds to a breakage that actually reached `main`
  through an auto-opened dependency PR: an AGP or Gradle major beyond what
  Flutter supports, the `jvmTarget` DSL Kotlin 2.4 removed, an action pinned to
  a mutable tag, and the `secrets`-in-step-`if:` gate. It runs in the fast test
  job, so a bad bump fails in seconds with an explanation instead of an opaque
  Gradle error part-way through a 20-minute Android build.
- The Android CI job runs `:app:signingReport` before the APK build, so a bad
  toolchain combination fails at configuration time and the log states whether
  the release variant resolved to real or debug signing.

### Fixed
- Android builds work again. The merged Dependabot bump to Android Gradle
  Plugin 9.3.0 requires Gradle 9.5+, drops the `kotlin-android` plugin, and
  makes Flutter 3.41.1's own Gradle plugin throw an NPE — `main` could not
  produce an APK. AGP is back on 8.11.1 and Dependabot now ignores major bumps
  for it until the pinned Flutter version supports AGP 9.
- Kotlin 2.4.10 removed the string-valued `android.kotlinOptions.jvmTarget`,
  which failed script compilation. Migrated to the `compilerOptions` DSL; the
  Kotlin bump itself is kept.
- Exported course files are named `<name>.srcourse.json` again. They were being
  written as `<name>.srcourse`, contradicting the documented format and the
  extension the importer expects.
- Map labels for marks that share a position no longer overlap: a start/finish
  buoy rounded twice now renders as one `1·5. SA7 Start/Finish` label, and any
  label that would still collide is nudged or dropped.
- The release workflow's Android signing steps never ran — they were gated on
  `secrets` in a step-level `if:`, where that context is not available. Signing
  now keys off a job-level env var, and the run reports whether the artifacts
  are signed.

### Changed
- The Flutter version is pinned in one place
  ([`.github/actions/setup-flutter`](.github/actions/setup-flutter/action.yml))
  and shared by every workflow, so a new Flutter stable release cannot break CI
  unannounced.
- All GitHub Actions are pinned to commit SHAs, with Dependabot keeping them
  current.
- Workflow permissions narrowed to least privilege: `contents: write` now
  applies only to the job that publishes a release, and Pages write scopes only
  to the deploy job.
- Secrets are passed to shell steps through `env:` rather than interpolated
  into the script body.
- Source reformatted with the Dart 3.11 formatter, which the pinned toolchain
  now enforces in CI.

## [1.0.1] — 2026-07-03

Baseline release. Live race navigation (distance, bearing, VMG, SOG/COG, ETA,
auto-advance), the course builder and library, bundled Chicago courses, GPX
recording and export, the offline course map, and Android/iOS/Web builds.

[Unreleased]: https://github.com/umutsoysal/SailRaceComputer/compare/v1.0.1-a6-i6...HEAD
[1.0.1]: https://github.com/umutsoysal/SailRaceComputer/releases/tag/v1.0.1-a6-i6
