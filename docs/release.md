# Release Packaging

This repository can package release-ready artifacts for Android, iOS, and Web both locally and in GitHub Actions.

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

1. Verify the tag matches `pubspec.yaml` via `tool/verify_release_version.dart`.
2. Build:
   - Android APK
   - Android App Bundle (`.aab`)
   - Web release tarball
   - Unsigned iOS `.app` bundle zip
3. Generate SHA-256 checksums.
4. Publish all assets to a GitHub Release.

Accepted tag examples:

- `v1.0.0`
- `v1.0.0+1`

Use the `+build` suffix when you want the Git tag to match the Flutter build number exactly.

## Repository secrets

For signed Android release builds in GitHub Actions, configure:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

The workflow decodes the keystore into `android/upload-keystore.jks` at runtime and writes `android/key.properties` dynamically.

## iOS note

GitHub Actions builds an unsigned iOS release bundle using `flutter build ios --release --no-codesign`. This validates the project and produces a distributable app bundle for QA handoff, but App Store delivery still requires your Apple signing identities and provisioning profiles outside CI.
