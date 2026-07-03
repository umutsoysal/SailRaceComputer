import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Small wrapper around Firebase Analytics so the rest of the app can log
/// meaningful product events without depending on plugin details.
class AppAnalytics {
  AppAnalytics._();

  static final instance = AppAnalytics._();

  FirebaseAnalytics? _analytics;
  bool _didAttemptInitialization = false;
  bool _initializing = false;

  bool get isEnabled => _analytics != null;

  Future<void> initialize() async {
    if (_analytics != null || _didAttemptInitialization || _initializing) {
      return;
    }

    _didAttemptInitialization = true;
    _initializing = true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _analytics = FirebaseAnalytics.instance;
      await _analytics!.setAnalyticsCollectionEnabled(true);
    } catch (error, stackTrace) {
      debugPrint(
        'Firebase analytics is disabled until FlutterFire is configured: '
        '$error',
      );
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _initializing = false;
    }
  }

  void logTabSelected(String tabName) {
    unawaited(
      _logEvent(
        'tab_selected',
        parameters: {'tab_name': tabName},
      ),
    );
  }

  void logLibraryOpened({required String source}) {
    unawaited(
      _logEvent(
        'library_opened',
        parameters: {'source': source},
      ),
    );
  }

  void logCourseSaved({
    required int buoyCount,
    required String source,
  }) {
    unawaited(
      _logEvent(
        'course_saved',
        parameters: {
          'buoy_count': buoyCount,
          'source': source,
        },
      ),
    );
  }

  void logRaceStarted({
    required int markCount,
    required int startOffsetMinutes,
  }) {
    unawaited(
      _logEvent(
        'race_started',
        parameters: {
          'mark_count': markCount,
          'start_offset_minutes': startOffsetMinutes,
        },
      ),
    );
  }

  void logRaceFinished({
    required int totalMarks,
    required int finalMarkIndex,
    required bool completedCourse,
    required int durationSeconds,
    required int trackPointCount,
  }) {
    unawaited(
      _logEvent(
        'race_finished',
        parameters: {
          'total_marks': totalMarks,
          'final_mark_index': finalMarkIndex,
          'completed_course': completedCourse ? 1 : 0,
          'duration_seconds': durationSeconds,
          'track_point_count': trackPointCount,
        },
      ),
    );
  }

  Future<void> _logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    final analytics = _analytics;
    if (analytics == null) return;

    try {
      await analytics.logEvent(name: name, parameters: parameters);
    } catch (error, stackTrace) {
      debugPrint('Failed to log analytics event `$name`: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
