import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_race_computer/models/course.dart';
import 'package:sail_race_computer/services/course_file.dart';
import 'package:sail_race_computer/utils/geo.dart';
import 'package:sail_race_computer/widgets/imported_course_picker_dialog.dart';

ImportedCourseDefinition _definition(
  String id,
  String name, {
  String? type,
  double? distanceNm,
}) => ImportedCourseDefinition(
  id: id,
  name: name,
  type: type,
  distanceNm: distanceNm,
  course: Course(
    name: name,
    buoys: [Buoy(name: 'Start', position: const LatLng(41.85, -87.55))],
  ),
);

ImportedCourseBundle _bundle(List<ImportedCourseDefinition> courses) =>
    ImportedCourseBundle(name: 'CCYC 2026', version: 2, courses: courses);

/// Pumps a host widget whose button opens the picker and records the result.
Future<void> _pumpPicker(
  WidgetTester tester,
  ImportedCourseBundle bundle, {
  String? sourceName,
  required void Function(ImportedCourseDefinition?) onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              onResult(
                await pickImportedCourse(
                  context,
                  bundle,
                  sourceName: sourceName,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('returns the only course without showing a dialog', (
    tester,
  ) async {
    ImportedCourseDefinition? result;
    var called = false;

    await _pumpPicker(
      tester,
      _bundle([_definition('a', 'Course A')]),
      onResult: (value) {
        result = value;
        called = true;
      },
    );

    expect(called, isTrue);
    expect(result?.id, 'a');
    expect(find.text('Choose course'), findsNothing);
  });

  testWidgets('throws when the bundle has no courses', (tester) async {
    Object? thrown;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                try {
                  await pickImportedCourse(context, _bundle(const []));
                } catch (error) {
                  thrown = error;
                }
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();

    expect(thrown, isA<CourseFileException>());
  });

  testWidgets('lists every course and returns the tapped one', (tester) async {
    ImportedCourseDefinition? result;

    await _pumpPicker(
      tester,
      _bundle([
        _definition('a', 'Course A', type: 'JAM', distanceNm: 4),
        _definition('b', 'Course B'),
        _definition('c', 'Course C'),
      ]),
      sourceName: 'ccyc.srcourse.json',
      onResult: (value) => result = value,
    );

    expect(find.text('Choose course'), findsOneWidget);
    expect(find.text('Course A'), findsOneWidget);
    expect(find.text('Course C'), findsOneWidget);
    expect(
      find.textContaining('contains 3 courses from ccyc.srcourse.json'),
      findsOneWidget,
    );
    // The summary line is only rendered for courses that have one.
    expect(find.text('a · JAM · 4 NM'), findsOneWidget);

    await tester.tap(find.text('Course B'));
    await tester.pumpAndSettle();

    expect(result?.id, 'b');
    expect(find.text('Choose course'), findsNothing);
  });

  testWidgets('omits the source phrase when no source name is given', (
    tester,
  ) async {
    await _pumpPicker(
      tester,
      _bundle([_definition('a', 'Course A'), _definition('b', 'Course B')]),
      onResult: (_) {},
    );

    expect(find.textContaining('contains 2 courses.'), findsOneWidget);
    expect(find.textContaining(' from '), findsNothing);
  });

  testWidgets('cancel returns null', (tester) async {
    ImportedCourseDefinition? result;
    var called = false;

    await _pumpPicker(
      tester,
      _bundle([_definition('a', 'Course A'), _definition('b', 'Course B')]),
      onResult: (value) {
        result = value;
        called = true;
      },
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(result, isNull);
  });
}
