FLUTTER ?= ./tool/flutterw.sh
DART ?= ./tool/dartw.sh
BASE_HREF ?= /

.PHONY: help bootstrap format analyze test coverage ci build-web build-apk build-appbundle build-ios-no-codesign build-all clean version version-tag version-check version-sync version-android version-ios version-patch version-minor version-major version-release-patch version-release-minor version-release-major

help:
	@printf '%s\n' \
		'bootstrap              Install Dart and Flutter dependencies' \
		'format                 Verify formatting for lib/, test/, tool/' \
		'analyze                Run flutter analyze' \
		'test                   Run flutter test' \
		'coverage               Run flutter test --coverage' \
		'ci                     Run the local CI validation suite' \
		'build-web              Build the web app (override BASE_HREF=/repo/)' \
		'build-apk              Build a release APK' \
		'build-appbundle        Build a release Android App Bundle' \
		'build-ios-no-codesign  Build an unsigned iOS release bundle (macOS only)' \
		'build-all              Build web + Android release artifacts' \
		'version                Show the public release version and internal platform counters' \
		'version-tag            Print the unique release automation tag' \
		'version-check          Validate app_version.json and pubspec sync' \
		'version-sync           Sync pubspec.yaml from app_version.json' \
		'version-android        Increment the Android build counter' \
		'version-ios            Increment the iOS build counter' \
		'version-patch          Increment the public patch release version' \
		'version-minor          Increment the public minor release version' \
		'version-major          Increment the public major release version' \
		'version-release-patch  Bump patch version and both platform counters' \
		'version-release-minor  Bump minor version and both platform counters' \
		'version-release-major  Bump major version and both platform counters' \
		'clean                  Remove generated build outputs'

bootstrap:
	$(FLUTTER) pub get

format:
	$(DART) format --output=none --set-exit-if-changed lib test tool

analyze: bootstrap
	$(FLUTTER) analyze

test: bootstrap
	$(FLUTTER) test

coverage: bootstrap
	$(FLUTTER) test --coverage

ci: bootstrap format analyze test build-web build-apk build-appbundle

version:
	$(DART) tool/version.dart current

version-tag:
	$(DART) tool/version.dart tag

version-check:
	$(DART) tool/version.dart check

version-sync:
	$(DART) tool/version.dart sync

version-patch:
	$(DART) tool/version.dart bump patch

version-minor:
	$(DART) tool/version.dart bump minor

version-major:
	$(DART) tool/version.dart bump major

version-release-patch:
	$(DART) tool/version.dart bump patch
	$(DART) tool/version.dart bump android
	$(DART) tool/version.dart bump ios

version-release-minor:
	$(DART) tool/version.dart bump minor
	$(DART) tool/version.dart bump android
	$(DART) tool/version.dart bump ios

version-release-major:
	$(DART) tool/version.dart bump major
	$(DART) tool/version.dart bump android
	$(DART) tool/version.dart bump ios

version-android:
	$(DART) tool/version.dart bump android

version-ios:
	$(DART) tool/version.dart bump ios

build-web: bootstrap
	$(FLUTTER) build web --release --base-href "$(BASE_HREF)" $(shell $(DART) tool/version.dart build-args web)

build-apk: bootstrap
	$(FLUTTER) build apk --release $(shell $(DART) tool/version.dart build-args android)

build-appbundle: bootstrap
	$(FLUTTER) build appbundle --release $(shell $(DART) tool/version.dart build-args android)

build-ios-no-codesign: bootstrap
	$(FLUTTER) build ios --release --no-codesign $(shell $(DART) tool/version.dart build-args ios)

build-all: build-web build-apk build-appbundle

clean:
	$(FLUTTER) clean
