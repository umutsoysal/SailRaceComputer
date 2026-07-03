# Release Packaging

This repository can package release-ready artifacts for Android, iOS, and Web both locally and in GitHub Actions.

## Versioning policy

Race Mate now treats versioning as:

- `x.y.z` = marketing version users see
- `+build` = one global ship counter that must always go up

Examples:

- `1.0.0+7`
- `1.0.1+8`
- `1.1.0+9`

This matters because Flutter maps the build number to:

- Android `versionCode`
- iOS `CFBundleVersion`

Those store-facing build numbers should keep increasing across releases.

## Local version commands

Use the repo tool instead of editing `pubspec.yaml` by hand:

```bash
make version
make version-build
make version-patch
make version-minor
make version-major
make version-tag
```

Recommended patterns:

- Hotfix rebuild without changing the user-visible version:
  - `make version-build`
- Small shipped fix:
  - `make version-patch`
- Feature release:
  - `make version-minor`
- Big milestone:
  - `make version-major`

`make version-tag` prints the exact git tag expected by the release workflow.

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
2. Verify the tag matches `pubspec.yaml` exactly via `tool/verify_release_version.dart`.
3. Build:
   - Android APK
   - Android App Bundle (`.aab`)
   - Web release tarball
   - Unsigned iOS `.app` bundle zip
4. Generate SHA-256 checksums.
5. Publish all assets to a GitHub Release.

Accepted tag examples:

- `v1.0.0+7`
- `v1.0.1+8`

The release workflow now expects the exact full version tag, including the
`+build` suffix.

## Shipping loop

For a normal release:

```bash
make version-patch
make ci
git commit -am "Release 1.0.1+8"
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
