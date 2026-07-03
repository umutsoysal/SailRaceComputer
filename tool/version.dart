import 'dart:convert';
import 'dart:io';

const _versionFilePath = 'app_version.json';
const _pubspecFilePath = 'pubspec.yaml';

void main(List<String> args) {
  if (args.isEmpty) {
    _usage(exitCode: 64);
  }

  final command = args.first;
  final rest = args.sublist(1);
  final pubspec = File(_pubspecFilePath);
  final versionFile = File(_versionFilePath);
  if (!pubspec.existsSync()) {
    stderr.writeln('$_pubspecFilePath not found.');
    exit(66);
  }
  if (!versionFile.existsSync()) {
    stderr.writeln('$_versionFilePath not found.');
    exit(66);
  }

  final originalPubspec = pubspec.readAsStringSync();
  final state = _parseVersionState(versionFile.readAsStringSync());
  final currentPubspecVersion = _parsePubspecVersion(originalPubspec);

  switch (command) {
    case 'current':
      stdout.writeln('public release: ${state.marketing}');
      stdout.writeln('release tag: ${state.releaseTag}');
      stdout.writeln('android build: ${state.androidBuild}');
      stdout.writeln('ios build: ${state.iosBuild}');
      stdout.writeln('pubspec version: ${currentPubspecVersion.display}');
      return;
    case 'tag':
      stdout.writeln(state.releaseTag);
      return;
    case 'value':
      if (rest.length != 1) {
        stderr.writeln(
          'Usage: dart tool/version.dart value <marketing|android-build|ios-build|pubspec-version|max-build>',
        );
        exit(64);
      }
      stdout.writeln(_valueForField(state, currentPubspecVersion, rest.single));
      return;
    case 'build-args':
      if (rest.length != 1) {
        stderr.writeln(
          'Usage: dart tool/version.dart build-args <android|ios|web>',
        );
        exit(64);
      }
      stdout.writeln(_buildArgsForPlatform(state, rest.single));
      return;
    case 'check':
      final expectedPubspec = state.pubspecVersion;
      if (currentPubspecVersion.display != expectedPubspec) {
        stderr.writeln(
          'pubspec.yaml version ${currentPubspecVersion.display} does not match '
          'expected $expectedPubspec from $_versionFilePath.',
        );
        stderr.writeln('Run `dart tool/version.dart sync` to repair it.');
        exit(65);
      }
      stdout.writeln(
        'Version metadata is valid. '
        'marketing=${state.marketing}, android=${state.androidBuild}, '
        'ios=${state.iosBuild}, pubspec=${currentPubspecVersion.display}.',
      );
      return;
    case 'sync':
      _writePubspecVersion(pubspec, originalPubspec, state.pubspecVersion);
      stdout.writeln('Synced pubspec.yaml to version ${state.pubspecVersion}.');
      return;
    case 'bump':
      if (rest.isEmpty) {
        stderr.writeln(
          'Usage: dart tool/version.dart bump <patch|minor|major|android|ios>',
        );
        exit(64);
      }
      final bumped = _bumpState(state, rest);
      versionFile.writeAsStringSync(_encodeVersionState(bumped));
      _writePubspecVersion(pubspec, originalPubspec, bumped.pubspecVersion);
      stdout.writeln(
        'Updated version metadata: marketing=${bumped.marketing}, '
        'android=${bumped.androidBuild}, ios=${bumped.iosBuild}',
      );
      stdout.writeln('Release tag: v${bumped.marketing}');
      stdout.writeln('pubspec version: ${bumped.pubspecVersion}');
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
  stderr.writeln('Usage: dart tool/version.dart <command>');
  stderr.writeln('');
  stderr.writeln('Commands:');
  stderr.writeln(
    '  current                         Show the public version and release metadata',
  );
  stderr.writeln(
    '  tag                             Print the exact automation tag',
  );
  stderr.writeln('  value <field>                   Print one version value');
  stderr.writeln(
    '  build-args <android|ios|web>    Print Flutter build args for a platform',
  );
  stderr.writeln(
    '  check                           Validate app_version.json and pubspec.yaml',
  );
  stderr.writeln(
    '  sync                            Sync pubspec.yaml from app_version.json',
  );
  stderr.writeln(
    '  bump patch                      Increment marketing patch version',
  );
  stderr.writeln(
    '  bump minor                      Increment marketing minor version',
  );
  stderr.writeln(
    '  bump major                      Increment marketing major version',
  );
  stderr.writeln(
    '  bump android                    Increment Android build number',
  );
  stderr.writeln(
    '  bump ios                        Increment iOS build number',
  );
  exit(exitCode);
}

_VersionState _parseVersionState(String contents) {
  final raw = jsonDecode(contents);
  if (raw is! Map<String, dynamic>) {
    stderr.writeln('$_versionFilePath must contain a JSON object.');
    exit(65);
  }

  final marketing = raw['marketing'];
  final androidBuild = raw['android_build'];
  final iosBuild = raw['ios_build'];
  if (marketing is! String ||
      !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(marketing) ||
      androidBuild is! int ||
      iosBuild is! int ||
      androidBuild < 1 ||
      iosBuild < 1) {
    stderr.writeln(
      '$_versionFilePath must contain: '
      '{"marketing":"x.y.z","android_build":number,"ios_build":number}.',
    );
    exit(65);
  }

  return _VersionState(
    marketing: marketing,
    androidBuild: androidBuild,
    iosBuild: iosBuild,
  );
}

_PubspecVersion _parsePubspecVersion(String pubspecContents) {
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

  return _PubspecVersion(
    marketing: '${match.group(1)}.${match.group(2)}.${match.group(3)}',
    build: int.parse(match.group(4)!),
  );
}

void _writePubspecVersion(
  File pubspec,
  String originalContents,
  String version,
) {
  final updated = originalContents.replaceFirst(
    RegExp(r'^version:\s*.+$', multiLine: true),
    'version: $version',
  );
  pubspec.writeAsStringSync(updated);
}

String _valueForField(
  _VersionState state,
  _PubspecVersion pubspecVersion,
  String field,
) {
  switch (field) {
    case 'marketing':
      return state.marketing;
    case 'android-build':
      return '${state.androidBuild}';
    case 'ios-build':
      return '${state.iosBuild}';
    case 'pubspec-version':
      return pubspecVersion.display;
    case 'max-build':
      return '${state.maxBuild}';
    default:
      stderr.writeln(
        'Unknown field `$field`. Use marketing, android-build, ios-build, '
        'pubspec-version, or max-build.',
      );
      exit(64);
  }
}

String _buildArgsForPlatform(_VersionState state, String platform) {
  switch (platform) {
    case 'android':
      return '--build-name ${state.marketing} --build-number ${state.androidBuild}';
    case 'ios':
      return '--build-name ${state.marketing} --build-number ${state.iosBuild}';
    case 'web':
      return '--build-name ${state.marketing}';
    default:
      stderr.writeln('Unknown platform `$platform`. Use android, ios, or web.');
      exit(64);
  }
}

_VersionState _bumpState(_VersionState state, List<String> args) {
  final target = args.first;
  switch (target) {
    case 'patch':
      return state.bumpPatch();
    case 'minor':
      return state.bumpMinor();
    case 'major':
      return state.bumpMajor();
    case 'android':
      return state.bumpAndroid();
    case 'ios':
      return state.bumpIos();
    default:
      stderr.writeln(
        'Unknown bump target `$target`. Use patch, minor, major, android, or ios.',
      );
      exit(64);
  }
}

String _encodeVersionState(_VersionState state) {
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert({'marketing': state.marketing, 'android_build': state.androidBuild, 'ios_build': state.iosBuild})}\n';
}

class _VersionState {
  const _VersionState({
    required this.marketing,
    required this.androidBuild,
    required this.iosBuild,
  });

  final String marketing;
  final int androidBuild;
  final int iosBuild;

  int get maxBuild => androidBuild > iosBuild ? androidBuild : iosBuild;
  String get pubspecVersion => '$marketing+$maxBuild';
  String get releaseTag => 'v$marketing-a$androidBuild-i$iosBuild';

  _VersionState bumpPatch() {
    final parts = marketing.split('.').map(int.parse).toList(growable: false);
    return _VersionState(
      marketing: '${parts[0]}.${parts[1]}.${parts[2] + 1}',
      androidBuild: androidBuild,
      iosBuild: iosBuild,
    );
  }

  _VersionState bumpMinor() {
    final parts = marketing.split('.').map(int.parse).toList(growable: false);
    return _VersionState(
      marketing: '${parts[0]}.${parts[1] + 1}.0',
      androidBuild: androidBuild,
      iosBuild: iosBuild,
    );
  }

  _VersionState bumpMajor() {
    final parts = marketing.split('.').map(int.parse).toList(growable: false);
    return _VersionState(
      marketing: '${parts[0] + 1}.0.0',
      androidBuild: androidBuild,
      iosBuild: iosBuild,
    );
  }

  _VersionState bumpAndroid() => _VersionState(
    marketing: marketing,
    androidBuild: androidBuild + 1,
    iosBuild: iosBuild,
  );

  _VersionState bumpIos() => _VersionState(
    marketing: marketing,
    androidBuild: androidBuild,
    iosBuild: iosBuild + 1,
  );
}

class _PubspecVersion {
  const _PubspecVersion({required this.marketing, required this.build});

  final String marketing;
  final int build;

  String get display => '$marketing+$build';
}
