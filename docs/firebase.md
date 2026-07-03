# Firebase Setup

Race Mate now includes Firebase core plus an analytics wrapper. The app will
still run before Firebase is configured, but analytics stays disabled until you
connect this checkout to a real Firebase project.

## What is already wired in code

- `lib/main.dart` initializes Firebase on startup.
- `lib/services/app_analytics.dart` wraps Firebase Analytics behind a small
  app-level API.
- The app logs product events for:
  - bottom-nav tab selection
  - opening the library
  - saving a course
  - starting a race
  - finishing a race
- `lib/firebase_options.dart` is a placeholder that exists only so the app can
  compile before configuration. `flutterfire configure` should replace it with
  the generated project-specific file.

## One-time project setup

1. Create a Firebase project in the Firebase console.
2. Enable Google Analytics for that project.
3. Install the Firebase CLI and FlutterFire CLI if you do not have them yet.
4. From the repo root, run:

```bash
flutterfire configure
```

5. Select the platforms you plan to ship from this repo:
   - iOS
   - Android
   - Web

The generated `lib/firebase_options.dart` should replace the placeholder in
this repo.

## Local dependency install

After configuration, fetch packages:

```bash
./tool/flutterw.sh pub get
```

## Current analytics events

The code intentionally avoids sending raw course names or GPX payloads as
analytics event parameters. Current events are:

- `tab_selected`
- `library_opened`
- `course_saved`
- `race_started`
- `race_finished`

## Auth later

If you decide to add accounts later, the next step would usually be:

```bash
./tool/flutterw.sh pub add firebase_auth
```

Then enable the provider you want in Firebase Authentication, such as:

- Anonymous auth for backend identity without a visible sign-in flow
- Email link or email/password for straightforward account ownership
- Apple or Google sign-in for consumer-friendly login
