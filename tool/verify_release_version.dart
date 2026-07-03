import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart tool/verify_release_version.dart <tag>');
    exit(64);
  }

  final rawTag = args.single.trim();
  final normalizedTag = rawTag.startsWith('refs/tags/')
      ? rawTag.substring(10)
      : rawTag;
  final expectedTag = normalizedTag.startsWith('v')
      ? normalizedTag
      : 'v$normalizedTag';

  final versionFile = File('app_version.json');
  if (!versionFile.existsSync()) {
    stderr.writeln('app_version.json not found.');
    exit(66);
  }

  final raw = jsonDecode(versionFile.readAsStringSync());
  if (raw is! Map<String, dynamic>) {
    stderr.writeln('app_version.json must contain a JSON object.');
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
      'app_version.json must contain valid marketing, android_build, and ios_build values.',
    );
    exit(65);
  }

  final currentTag = 'v$marketing-a$androidBuild-i$iosBuild';
  if (currentTag != expectedTag) {
    stderr.writeln(
      'Tag $normalizedTag does not match release metadata for $marketing. '
      'Use tag $currentTag.',
    );
    exit(1);
  }

  stdout.writeln('Verified release version $marketing for tag $normalizedTag.');
}
