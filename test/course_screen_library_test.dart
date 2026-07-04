import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sail_race_computer/app_shell.dart';
import 'package:sail_race_computer/models/course.dart';
import 'package:sail_race_computer/services/race_session_store.dart';
import 'package:sail_race_computer/utils/geo.dart';
import 'package:sail_race_computer/widgets/recording_map_preview.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'bottom navigation exposes a single courses tab plus recordings and settings',
      (
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
        track: [
          RaceTrackPoint(
            recordedAt: DateTime.utc(2026, 7, 2, 23, 40),
            latitude: 41.88,
            longitude: -87.62,
            accuracyM: 5,
            speedMs: 2.4,
            headingDeg: 35,
            altitudeM: 180,
          ),
          RaceTrackPoint(
            recordedAt: DateTime.utc(2026, 7, 2, 23, 45),
            latitude: 41.885,
            longitude: -87.615,
            accuracyM: 5,
            speedMs: 2.8,
            headingDeg: 42,
            altitudeM: 180,
          ),
        ],
      ),
    );
    await raceStore.saveCompleted(
      RaceSessionRecord(
        courseName: 'Columbia Yacht Club',
        startedAt: DateTime.utc(2026, 7, 3, 23, 40),
        finishedAt: DateTime.utc(2026, 7, 3, 23, 50),
        totalMarks: 2,
        finalMarkIndex: 1,
        completedCourse: true,
        track: [
          RaceTrackPoint(
            recordedAt: DateTime.utc(2026, 7, 3, 23, 40),
            latitude: 41.89,
            longitude: -87.61,
            accuracyM: 5,
            speedMs: 2.1,
            headingDeg: 28,
            altitudeM: 180,
          ),
          RaceTrackPoint(
            recordedAt: DateTime.utc(2026, 7, 3, 23, 45),
            latitude: 41.894,
            longitude: -87.605,
            accuracyM: 5,
            speedMs: 2.7,
            headingDeg: 37,
            altitudeM: 180,
          ),
        ],
      ),
    );
    expect(await raceStore.listSaved(), hasLength(2));

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

    expect(find.text('Race'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Courses'), findsWidgets);
    expect(find.text('Recordings'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Courses').last);
    await tester.pumpAndSettle();

    expect(find.text('Selected course'), findsOneWidget);
    expect(find.text('Harbor Start'), findsOneWidget);
    expect(find.text('Edit course'), findsOneWidget);
    expect(find.text('New course'), findsOneWidget);
    expect(find.byKey(const Key('course-group-filter')), findsOneWidget);
    expect(find.text('Bundled Courses'), findsOneWidget);
    expect(find.text('Saved Courses'), findsNothing);
    expect(find.text('Recorded Races'), findsNothing);

    await tester.tap(find.byKey(const Key('course-group-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CCYC Race Courses 2026').last);
    await tester.pumpAndSettle();

    expect(find.text('CCYC Race Courses 2026'), findsWidgets);
    expect(
      find.text('Columbia YC Wednesday Night Beer Can Series 2026'),
      findsNothing,
    );

    await tester.tap(find.text('Recordings'));
    await tester.pumpAndSettle();

    expect(find.text('Recorded Races'), findsOneWidget);
    expect(find.byKey(const Key('library-group-filter')), findsOneWidget);

    await tester.tap(find.byKey(const Key('library-group-filter')));
    await tester.pumpAndSettle();
    expect(find.text('Wednesday Series').last, findsOneWidget);
    expect(find.text('Columbia Yacht Club').last, findsOneWidget);
    await tester.tap(find.text('Wednesday Series').last);
    await tester.pumpAndSettle();

    expect(find.text('Wednesday Series'), findsWidgets);
    expect(find.text('Columbia Yacht Club'), findsNothing);
    expect(find.byTooltip('Race actions'), findsOneWidget);
    expect(find.byType(RecordingMapPreview), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('General App Settings'), findsOneWidget);
    expect(find.text('Feedback'), findsOneWidget);
    expect(find.text('App Version'), findsOneWidget);
    expect(find.text('Version 1.0.1'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Privacy'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();

    expect(find.text('Privacy Policy'), findsWidgets);
    expect(find.text('Effective July 3, 2026'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Where data is stored'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Where data is stored'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Terms of Use'), findsOneWidget);

    await tester.tap(find.text('Terms of Use'));
    await tester.pumpAndSettle();

    expect(find.text('Terms of Use'), findsWidgets);
    expect(find.text('Safety and accuracy'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Disclaimer and limits'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Disclaimer and limits'), findsOneWidget);
  });
}
