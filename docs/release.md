# Release Packaging

This repository can package release-ready artifacts for Android, iOS, and Web both locally and in GitHub Actions.

## Versioning policy

Race Mate now uses one public release version plus hidden platform build counters.

- Public release version:
  - `x.y.z`
- Internal counters:
  - Android build number
  - iOS build number

Examples:

- public release: `1.0.0`
- Android build: `5`
- iOS build: `7`

This matters because Flutter maps the build number to:

- Android `versionCode`
- iOS `CFBundleVersion`

Those store-facing build numbers should keep increasing for each platform, even
if one platform skips a release and catches up later.

The source of truth is `app_version.json`.
`pubspec.yaml` is synced automatically to:

```text
<marketing version>+<max(android_build, ios_build)>
```

That pubspec suffix is internal plumbing, not your public release version.

## Local version commands

Use the repo tool instead of editing `pubspec.yaml` by hand:

```bash
make version
make version-patch
make version-minor
make version-major
make version-release-patch
make version-release-minor
make version-release-major
make version-android
make version-ios
make version-tag
```

Recommended patterns:

- Small shipped fix with a new public release:
  - `make version-patch`
- Small shipped fix on both platforms:
  - `make version-release-patch`
- Feature release:
  - `make version-release-minor`
- Big milestone:
  - `make version-release-major`
- Android-only catch-up build:
  - `make version-android`
- iOS-only catch-up build:
  - `make version-ios`

`make version-tag` prints the unique automation tag expected by the release workflow.
Example:

- public release: `1.0.0`
- automation tag: `v1.0.0-a5-i7`

That tag stays unique even when Android or iOS catches up later, while the app
still shows the single public release version `1.0.0`.

## Local build commands

Use the checked-in wrapper so builds work whether Flutter is on `PATH` or installed at `$HOME/flutter/bin/flutter`.

```bash
make ci
make build-all
make build-ios-no-codesign   # macOS only
```

Useful one-off targets:

- `make build-web BASE_HREF=/SailRaceComputer/`
- `make build-apk`
- `make build-appbundle`

## Android signing

Release signing is automatic when either of these is present:

1. `android/key.properties`
2. Environment variables:
   - `ANDROID_KEYSTORE_PATH`
   - `ANDROID_KEYSTORE_PASSWORD`
   - `ANDROID_KEY_ALIAS`
   - `ANDROID_KEY_PASSWORD`

Example `android/key.properties`:

```properties
storeFile=upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

If release signing is not configured, local and CI release builds fall back to the debug keystore so packaging validation still succeeds.

## GitHub release workflow

The `.github/workflows/release.yml` workflow runs on tags that start with `v`.

It will:

1. Validate `pubspec.yaml` version format via `tool/version.dart check`.
2. Verify the release tag matches `app_version.json` via `tool/verify_release_version.dart`.
3. Build:
   - Android APK
   - Android App Bundle (`.aab`)
   - Web release tarball
   - Unsigned iOS `.app` bundle zip
4. Generate SHA-256 checksums.
5. Publish all assets to a GitHub Release.

Accepted tag examples:

- `v1.0.0-a5-i5`
- `v1.0.1-a6-i6`

The release workflow expects the marketing version plus the current Android and
iOS counters in the tag. That keeps each automation run unique without creating
multiple user-facing version names.

## Shipping loop

For a release on both platforms:

```bash
make version-release-patch
make ci
git commit -am "Release 1.0.1"
git tag "$(make -s version-tag)"
git push origin main --tags
```

For an Android-only catch-up release without changing the public release name:

```bash
make version-android
make ci
git commit -am "Android catch-up build for 1.0.1"
git tag "$(make -s version-tag)"
git push origin main --tags
```

## Repository secrets

For signed Android release builds in GitHub Actions, configure:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

The workflow decodes the keystore into `android/upload-keystore.jks` at runtime and writes `android/key.properties` dynamically.

## iOS note

GitHub Actions builds an unsigned iOS release bundle using `flutter build ios --release --no-codesign`. This validates the project and produces a distributable app bundle for QA handoff, but App Store delivery still requires your Apple signing identities and provisioning profiles outside CI.
