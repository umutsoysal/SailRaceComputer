import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the build toolchain against dependency bumps that compile fine on
/// paper but leave the app unbuildable.
///
/// Every constraint here corresponds to a breakage that actually reached
/// `main` via an auto-opened dependency PR. These run in the fast test job, so
/// a bad bump fails in seconds with an explanation instead of an opaque Gradle
/// error part-way through a 20-minute Android build.
///
/// When the pinned Flutter version moves, revisit the whole matrix together —
/// AGP, Gradle, and Kotlin are not independent knobs.
void main() {
  final settingsGradle = File('android/settings.gradle.kts');
  final wrapperProperties = File(
    'android/gradle/wrapper/gradle-wrapper.properties',
  );
  final appGradle = File('android/app/build.gradle.kts');
  final setupFlutter = File('.github/actions/setup-flutter/action.yml');
  final readme = File('README.md');

  /// Extracts the first capture group of [pattern] from [file].
  String extract(File file, RegExp pattern, String what) {
    expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
    final match = pattern.firstMatch(file.readAsStringSync());
    expect(
      match,
      isNotNull,
      reason:
          'Could not find $what in ${file.path}. If the file was '
          'restructured, update this test rather than deleting it.',
    );
    return match!.group(1)!;
  }

  int majorOf(String version) => int.parse(version.split('.').first);

  group('Android toolchain', () {
    test('Android Gradle Plugin stays on a major Flutter supports', () {
      final agp = extract(
        settingsGradle,
        RegExp(r'id\("com\.android\.application"\)\s+version\s+"([^"]+)"'),
        'the com.android.application version',
      );

      expect(
        majorOf(agp),
        8,
        reason:
            'AGP is pinned to 8.x (found $agp).\n'
            'AGP 9 removes the `kotlin-android` plugin, requires Gradle 9.5+, '
            'and makes the Flutter Gradle plugin throw an NPE while applying, '
            'so the Android build cannot run at all.\n'
            'If you are deliberately migrating, bump Flutter first, then '
            'update this expectation and the ignore rule in '
            '.github/dependabot.yml together.',
      );
    });

    test('Gradle wrapper stays on a major AGP 8 supports', () {
      final gradle = extract(
        wrapperProperties,
        RegExp(r'distributionUrl=.*?gradle-([0-9.]+)-(?:all|bin)\.zip'),
        'the Gradle distribution version',
      );

      expect(
        majorOf(gradle),
        8,
        reason:
            'The Gradle wrapper is pinned to 8.x (found $gradle).\n'
            'AGP 8.11.1 cannot create its problem-reporter service on Gradle 9, '
            'so configuration fails before anything is built.\n'
            'Gradle and AGP move together — bump both, or neither.',
      );
    });

    test('Kotlin plugin is 2.x', () {
      final kotlin = extract(
        settingsGradle,
        RegExp(
          r'id\("org\.jetbrains\.kotlin\.android"\)\s+version\s+"([^"]+)"',
        ),
        'the org.jetbrains.kotlin.android version',
      );

      expect(
        majorOf(kotlin),
        2,
        reason: 'Kotlin is pinned to 2.x (found $kotlin).',
      );
    });

    test('does not use the jvmTarget DSL Kotlin 2.4 removed', () {
      final source = appGradle.readAsStringSync();

      // Kotlin 2.4 turned `android.kotlinOptions.jvmTarget = "<string>"` into a
      // hard error; the replacement is the compilerOptions DSL. Comments that
      // merely mention the old name are fine, so match the assignment itself.
      expect(
        RegExp(
          r'^\s*jvmTarget\s*=\s*.*toString\(\)',
          multiLine: true,
        ).hasMatch(source),
        isFalse,
        reason:
            'android/app/build.gradle.kts assigns a String to jvmTarget. '
            'Kotlin 2.4 removed that DSL — use '
            '`kotlin { compilerOptions { jvmTarget = JvmTarget.JVM_17 } }`.',
      );
      expect(
        source.contains('JvmTarget.JVM_17'),
        isTrue,
        reason:
            'The Kotlin jvmTarget should still be set explicitly to 17 '
            'so it matches the Java source/target compatibility.',
      );
    });
  });

  group('Flutter pin', () {
    test('the CI pin and the README agree', () {
      final pinned = extract(
        setupFlutter,
        RegExp(r'''default:\s*["']([0-9]+\.[0-9]+\.[0-9]+)["']'''),
        'the pinned flutter-version default',
      );
      final documented = extract(
        readme,
        RegExp(r'\| Flutter \| ([0-9]+\.[0-9]+\.[0-9]+)'),
        'the Flutter version in the prerequisites table',
      );

      expect(
        documented,
        pinned,
        reason:
            'README documents Flutter $documented but CI installs $pinned. '
            'Bump both in the same change so contributors are not sent after '
            'the wrong SDK.',
      );
    });
  });

  group('Workflow hygiene', () {
    test('every third-party action is pinned to a commit SHA', () {
      final workflows = Directory(
        '.github/workflows',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.yml'));

      expect(workflows, isNotEmpty);

      final uses = RegExp(r'^\s*(?:-\s+)?uses:\s*(\S+)', multiLine: true);
      final offenders = <String>[];

      for (final workflow in workflows) {
        for (final match in uses.allMatches(workflow.readAsStringSync())) {
          final ref = match.group(1)!;
          // Local composite actions are referenced by path, not by version.
          if (ref.startsWith('./')) continue;
          final pin = ref.split('@').last;
          if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(pin)) {
            offenders.add('${workflow.uri.pathSegments.last}: $ref');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'These actions are referenced by a mutable tag instead of a commit '
            'SHA:\n  ${offenders.join('\n  ')}\n'
            'A tag can be moved under us. Pin the 40-character SHA and put the '
            'version in a trailing comment; Dependabot updates both.',
      );
    });

    test('the release workflow does not gate steps on the secrets context', () {
      final release = File('.github/workflows/release.yml').readAsStringSync();

      // `secrets` is not available to step-level `if:`. A gate written that way
      // silently evaluates false, so the step never runs — which is how tagged
      // releases shipped unsigned Android artifacts for months.
      expect(
        RegExp(r'if:.*secrets\.').hasMatch(release),
        isFalse,
        reason:
            'A step in release.yml is gated on the `secrets` context, which is '
            'not available to step-level `if:` and always evaluates false. '
            'Hoist the check into a job-level `env:` value instead.',
      );
    });
  });
}
