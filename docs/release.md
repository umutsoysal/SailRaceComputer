# Release Packaging

This repository can package release-ready artifacts for Android, iOS, and Web both locally and in GitHub Actions.

## Getting an installable APK

There are two paths, depending on whether you are cutting a real release.

### On demand — the "Package APK" workflow

For a build you can hand to a tester today, without touching the version or
creating a tag: **Actions → Package APK → Run workflow**.

| Input | Default | Effect |
|-------|---------|--------|
| `universal` | on | Also build the ~50MB APK that runs on any device |
| `publish` | off | Also attach the APKs to the rolling `latest-build` prerelease |

Every run uploads the APKs as workflow artifacts (kept 30 days) and writes a
summary table listing each file, its size, and which devices it targets. With
`publish` ticked, the same files are attached to a `latest-build` prerelease —
one moving tag, so testers can bookmark a single download page. It is marked
prerelease so it never looks like a real version.

The workflow builds one APK per ABI:

| File | Size | Install on |
|------|------|------------|
| `…-arm64-v8a.apk` | ~18MB | Nearly every phone from ~2017 onward — **start here** |
| `…-armeabi-v7a.apk` | ~16MB | Older 32-bit ARM devices |
| `…-x86_64.apk` | ~20MB | Emulators and x86 Chromebooks |
| `…-universal.apk` | ~50MB | Anything, at ~3x the download |

Filenames carry the version, the Android build counter, and the commit:
`race-mate-1.0.1-b6-a1b2c3d-arm64-v8a.apk`. `SHA256SUMS.txt` ships alongside.

Signing follows the same rule as the release workflow: with
`ANDROID_KEYSTORE_BASE64` configured the APKs are signed with the upload
keystore, and without it they are debug-signed. The run summary always states
which happened. A debug-signed APK installs fine for testing but cannot update
a Play Store install.

To install one, download it on the phone and open it — Android will ask for
permission to install from that browser or file manager the first time.

### On demand — the "Package AAB" workflow

Google Play requires an **App Bundle (`.aab`)** for new submissions and
updates — a plain APK is not accepted there. To get one without cutting a
release: **Actions → Package AAB → Run workflow**.

The workflow refuses to run without `ANDROID_KEYSTORE_BASE64` and the other
signing secrets configured — Play Console rejects a debug-signed bundle, so
there is no unsigned fallback here (unlike Package APK). Once it succeeds, the
`.aab` is available as a workflow artifact (kept 30 days) and a run summary
shows the filename and version. Download it and upload it directly in Play
Console under your app's Release → the track you want.

### Tagged releases

Pushing a `v*` tag runs `release.yml`, which publishes the per-ABI APKs, the
universal APK, the App Bundle, the Web tarball, an unsigned iOS bundle, and
`SHA256SUMS.txt` to a GitHub Release. See "Versioning policy" below for how to
produce the tag.

### Locally

```bash
make build-apk                                    # universal APK
./tool/flutterw.sh build apk --release --split-per-abi
```

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
make ship
make ship-patch
make ship-minor
make ship-major
make ship-android
make ship-ios
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

- Day-to-day easiest command to inspect the current version:
  - `make ship`
- Small shipped fix on both platforms:
  - `make ship-patch`
- Feature release on both platforms:
  - `make ship-minor`
- Big milestone on both platforms:
  - `make ship-major`
- Android-only catch-up build:
  - `make ship-android`
- iOS-only catch-up build:
  - `make ship-ios`

`make version-tag` prints the unique automation tag expected by the release workflow.
Example:

- public release: `1.0.0`
- automation tag: `v1.0.0-a5-i7`

That tag stays unique even when Android or iOS catches up later, while the app
still shows the single public release version `1.0.0`.

`make ship-*` targets already run `make ci` for you after bumping the version,
so they are the simplest safe commands to use most of the time.

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
make ship-patch
git commit -am "Release 1.0.1"
git tag "$(make -s version-tag)"
git push origin main --tags
```

For an Android-only catch-up release without changing the public release name:

```bash
make ship-android
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
