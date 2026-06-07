// Dev-only entrypoint. Run with:
//   flutter run -t lib/dev/sim_main.dart -d chrome   (or macos / any device)
//
// This is NOT shipped in the production app. The production entrypoint is
// lib/main.dart and does not import anything under lib/dev/.

import 'package:flutter/material.dart';
import 'simulator_screen.dart';

void main() {
  runApp(const SimulatorApp());
}

class SimulatorApp extends StatelessWidget {
  const SimulatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Race Mate — Simulator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6FB8)),
        useMaterial3: true,
      ),
      home: const SimulatorScreen(),
    );
  }
}
