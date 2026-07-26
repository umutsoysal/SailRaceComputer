import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sail_race_computer/screens/settings_screen.dart';

void main() {
  testWidgets('shows the bundled app version on the settings screen', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('App Version'), findsOneWidget);
    expect(find.text('Version 1.0.1'), findsOneWidget);
  });
}
