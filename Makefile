FLUTTER ?= ./tool/flutterw.sh
DART ?= ./tool/dartw.sh
BASE_HREF ?= /

.PHONY: help bootstrap format analyze test coverage ci build-web build-apk build-appbundle build-ios-no-codesign build-all clean version version-tag version-check version-build version-patch version-minor version-major

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
		'version                Show the current app version and release tag' \
		'version-tag            Print the exact git tag for the current version' \
		'version-check          Validate version format (x.y.z+build)' \
		'version-build          Increment the build number only' \
		'version-patch          Increment patch and build number' \
		'version-minor          Increment minor and build number' \
		'version-major          Increment major and build number' \
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
	$(DART) run tool/version.dart current

version-tag:
	$(DART) run tool/version.dart tag

version-check:
	$(DART) run tool/version.dart check

version-build:
	$(DART) run tool/version.dart bump build

version-patch:
	$(DART) run tool/version.dart bump patch

version-minor:
	$(DART) run tool/version.dart bump minor

version-major:
	$(DART) run tool/version.dart bump major

build-web: bootstrap
	$(FLUTTER) build web --release --base-href "$(BASE_HREF)"

build-apk: bootstrap
	$(FLUTTER) build apk --release

build-appbundle: bootstrap
	$(FLUTTER) build appbundle --release

build-ios-no-codesign: bootstrap
	$(FLUTTER) build ios --release --no-codesign

build-all: build-web build-apk build-appbundle

clean:
	$(FLUTTER) clean
