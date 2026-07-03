import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sail_race_computer/app_shell.dart';
import 'package:sail_race_computer/models/course.dart';
import 'package:sail_race_computer/services/race_session_store.dart';
import 'package:sail_race_computer/utils/geo.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('bottom navigation exposes library and settings tabs', (
    tester,
  ) async {
    final raceStore = RaceSessionStore();
    await raceStore.saveCompleted(
      RaceSessionRecord(
        courseName: 'Wednesday Series',
        startedAt: DateTime.utc(2026, 7, 2, 23, 40),
        finishedAt: DateTime.utc(2026, 7, 2, 23, 50),
        totalMarks: 3,
        finalMarkIndex: 2,
        completedCourse: true,
        track: const [],
      ),
    );
    expect(await raceStore.listSaved(), hasLength(1));

    final course = Course(
      name: 'Harbor Start',
      buoys: [Buoy(name: 'Start', position: const LatLng(41.88, -87.62))],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(course: course, onCourseChanged: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Course'), findsOneWidget);
    expect(find.text('Race'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    expect(find.text('Races'), findsOneWidget);
    expect(find.text('Wednesday Series'), findsOneWidget);
    expect(find.byTooltip('View GPX'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('General App Settings'), findsOneWidget);
    expect(find.text('Feedback'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Privacy'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Terms of Use'), findsOneWidget);
  });
}
