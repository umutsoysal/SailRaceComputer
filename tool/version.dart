import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    _usage(exitCode: 64);
  }

  final command = args.first;
  final rest = args.sublist(1);
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('pubspec.yaml not found.');
    exit(66);
  }

  final original = pubspec.readAsStringSync();
  final version = _parseVersion(original);

  switch (command) {
    case 'current':
      stdout.writeln(version.display);
      stdout.writeln('tag: v${version.display}');
      stdout.writeln('marketing: ${version.marketing}');
      stdout.writeln('build: ${version.build}');
      return;
    case 'tag':
      stdout.writeln('v${version.display}');
      return;
    case 'check':
      stdout.writeln(
        'Version ${version.display} is valid. '
        'Marketing=${version.marketing}, build=${version.build}.',
      );
      return;
    case 'bump':
      if (rest.length != 1) {
        stderr.writeln(
          'Usage: dart run tool/version.dart bump <build|patch|minor|major>',
        );
        exit(64);
      }
      final bumped = _bumpVersion(version, rest.single);
      final updated = original.replaceFirst(
        RegExp(r'^version:\s*.+$', multiLine: true),
        'version: ${bumped.display}',
      );
      pubspec.writeAsStringSync(updated);
      stdout
          .writeln('Updated version: ${version.display} -> ${bumped.display}');
      stdout.writeln('Next release tag: v${bumped.display}');
      return;
    default:
      _usage(error: 'Unknown command `$command`.', exitCode: 64);
  }
}

Never _usage({String? error, required int exitCode}) {
  if (error != null) {
    stderr.writeln(error);
    stderr.writeln('');
  }
  stderr.writeln('Usage: dart run tool/version.dart <command>');
  stderr.writeln('');
  stderr.writeln('Commands:');
  stderr.writeln(
      '  current               Show the current version and release tag');
  stderr.writeln(
      '  tag                   Print the exact release tag for the current version');
  stderr.writeln('  check                 Validate the version format');
  stderr.writeln('  bump build            Increment the build number only');
  stderr.writeln('  bump patch            Increment patch and build');
  stderr.writeln(
      '  bump minor            Increment minor, reset patch, increment build');
  stderr.writeln(
      '  bump major            Increment major, reset minor+patch, increment build');
  exit(exitCode);
}

_Version _parseVersion(String pubspecContents) {
  final match = RegExp(
    r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$',
    multiLine: true,
  ).firstMatch(pubspecContents);
  if (match == null) {
    stderr.writeln(
      'Unable to find a valid `version: x.y.z+build` entry in pubspec.yaml.',
    );
    exit(65);
  }

  final major = int.parse(match.group(1)!);
  final minor = int.parse(match.group(2)!);
  final patch = int.parse(match.group(3)!);
  final build = int.parse(match.group(4)!);
  if (build < 1) {
    stderr.writeln('Build number must be >= 1. Found $build.');
    exit(65);
  }

  return _Version(
    major: major,
    minor: minor,
    patch: patch,
    build: build,
  );
}

_Version _bumpVersion(_Version version, String target) {
  switch (target) {
    case 'build':
      return version.bumpBuild();
    case 'patch':
      return version.bumpPatch();
    case 'minor':
      return version.bumpMinor();
    case 'major':
      return version.bumpMajor();
    default:
      stderr.writeln(
        'Unknown bump target `$target`. Use build, patch, minor, or major.',
      );
      exit(64);
  }
}

class _Version {
  const _Version({
    required this.major,
    required this.minor,
    required this.patch,
    required this.build,
  });

  final int major;
  final int minor;
  final int patch;
  final int build;

  String get marketing => '$major.$minor.$patch';
  String get display => '$marketing+$build';

  _Version bumpBuild() => _Version(
        major: major,
        minor: minor,
        patch: patch,
        build: build + 1,
      );

  _Version bumpPatch() => _Version(
        major: major,
        minor: minor,
        patch: patch + 1,
        build: build + 1,
      );

  _Version bumpMinor() => _Version(
        major: major,
        minor: minor + 1,
        patch: 0,
        build: build + 1,
      );

  _Version bumpMajor() => _Version(
        major: major + 1,
        minor: 0,
        patch: 0,
        build: build + 1,
      );
}
