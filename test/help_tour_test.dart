import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sail_race_computer/widgets/help_tour.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A host with two keyed targets: one near the top of the screen and one near
/// the bottom, so both card placement branches get exercised.
class _TourHost extends StatelessWidget {
  const _TourHost({
    required this.topKey,
    required this.bottomKey,
    required this.steps,
    this.onStepShown,
  });

  final GlobalKey topKey;
  final GlobalKey bottomKey;
  final List<HelpTourStep> Function() steps;
  final ValueChanged<int>? onStepShown;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Container(key: topKey, height: 60, color: Colors.blue),
            const Spacer(),
            Builder(
              builder: (inner) => TextButton(
                onPressed: () => HelpTour.show(
                  inner,
                  steps: steps(),
                  onStepShown: onStepShown,
                ),
                child: const Text('start tour'),
              ),
            ),
            const Spacer(),
            Container(key: bottomKey, height: 60, color: Colors.green),
          ],
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // dismiss() marks the tour seen without awaiting, so drain that write
    // before resetting prefs or it leaks into the next test.
    HelpTour.dismiss();
    await Future<void>.delayed(Duration.zero);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(HelpTour.dismiss);

  group('HelpTour.hasSeen', () {
    test('is false before the tour runs', () async {
      expect(await HelpTour.hasSeen(), isFalse);
    });

    test('is true once the tour has been dismissed', () async {
      HelpTour.dismiss();
      // dismiss() writes the flag without awaiting; let the write land.
      await Future<void>.delayed(Duration.zero);

      expect(await HelpTour.hasSeen(), isTrue);
    });
  });

  group('HelpTour overlay', () {
    Future<void> startTour(
      WidgetTester tester, {
      required GlobalKey topKey,
      required GlobalKey bottomKey,
      List<int>? shownSteps,
    }) async {
      await tester.pumpWidget(
        _TourHost(
          topKey: topKey,
          bottomKey: bottomKey,
          onStepShown: shownSteps?.add,
          steps: () => [
            const HelpTourStep(title: 'Welcome', body: 'A quick tour.'),
            HelpTourStep(
              targetKey: topKey,
              title: 'Top thing',
              body: 'Lives near the top.',
            ),
            HelpTourStep(
              targetKey: bottomKey,
              title: 'Bottom thing',
              body: 'Lives near the bottom.',
            ),
          ],
        ),
      );
      await tester.tap(find.text('start tour'));
      await tester.pumpAndSettle();
    }

    testWidgets('walks forward through every step and finishes', (
      tester,
    ) async {
      final shown = <int>[];
      await startTour(
        tester,
        topKey: GlobalKey(),
        bottomKey: GlobalKey(),
        shownSteps: shown,
      );

      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('1 of 3'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Back'), findsNothing);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Top thing'), findsOneWidget);
      expect(find.text('2 of 3'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Bottom thing'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Bottom thing'), findsNothing);
      expect(shown, [0, 1, 2]);
    });

    testWidgets('Back returns to the previous step', (tester) async {
      await startTour(tester, topKey: GlobalKey(), bottomKey: GlobalKey());

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('1 of 3'), findsOneWidget);
    });

    testWidgets('tapping the scrim advances the tour', (tester) async {
      await startTour(tester, topKey: GlobalKey(), bottomKey: GlobalKey());

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Top thing'), findsOneWidget);
    });

    testWidgets('Skip closes the tour and records it as seen', (tester) async {
      await startTour(tester, topKey: GlobalKey(), bottomKey: GlobalKey());

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome'), findsNothing);
      expect(await HelpTour.hasSeen(), isTrue);
    });

    testWidgets('a second show() while visible is ignored', (tester) async {
      await startTour(tester, topKey: GlobalKey(), bottomKey: GlobalKey());

      await tester.tap(find.text('start tour'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Welcome'), findsOneWidget);
    });

    testWidgets('an empty step list shows nothing', (tester) async {
      await tester.pumpWidget(
        _TourHost(
          topKey: GlobalKey(),
          bottomKey: GlobalKey(),
          steps: () => const [],
        ),
      );
      await tester.tap(find.text('start tour'));
      await tester.pumpAndSettle();

      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('Next'), findsNothing);
    });
  });
}
