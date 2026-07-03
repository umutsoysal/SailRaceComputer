import 'dart:io';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/verify_release_version.dart <tag>');
    exit(64);
  }

  final rawTag = args.single.trim();
  final normalizedTag = rawTag.startsWith('refs/tags/')
      ? rawTag.substring(10)
      : rawTag;
  final expectedVersion = normalizedTag.startsWith('v')
      ? normalizedTag.substring(1)
      : normalizedTag;

  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('pubspec.yaml not found.');
    exit(66);
  }

  final versionLine = pubspec
      .readAsLinesSync()
      .map((line) => line.trim())
      .firstWhere((line) => line.startsWith('version:'), orElse: () => '');

  if (versionLine.isEmpty) {
    stderr.writeln('Unable to find a version entry in pubspec.yaml.');
    exit(65);
  }

  final currentVersion = versionLine.substring('version:'.length).trim();
  if (!currentVersion.startsWith(expectedVersion)) {
    stderr.writeln(
      'Tag $normalizedTag does not match pubspec version $currentVersion.',
    );
    exit(1);
  }

  stdout.writeln(
    'Verified pubspec version $currentVersion for tag $normalizedTag.',
  );
}
