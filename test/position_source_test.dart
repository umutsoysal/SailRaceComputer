import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sail_race_computer/services/position_source.dart';

/// The smallest legal [PositionSource]: it overrides only the two required
/// members, so the defaults of the optional ones are what gets exercised.
class _MinimalSource implements PositionSource {
  @override
  Future<String?> ensureReady() async => null;

  @override
  Stream<Position> get stream => const Stream<Position>.empty();

  @override
  Future<Position?> getInitialPosition() async => null;

  @override
  Future<Position?> getRecoveryPosition() async => null;

  @override
  Future<void> dispose() async {}
}

void main() {
  group('error classification', () {
    test('recognises the services-disabled message', () {
      expect(
        isLocationServicesDisabledError(locationServicesDisabledMessage),
        isTrue,
      );
      expect(
        isLocationServicesDisabledError(locationPermissionDeniedMessage),
        isFalse,
      );
      expect(isLocationServicesDisabledError('something else'), isFalse);
    });

    test('recognises both permission-denied messages', () {
      expect(
        isLocationPermissionError(locationPermissionDeniedMessage),
        isTrue,
      );
      expect(
        isLocationPermissionError(locationPermissionDeniedForeverMessage),
        isTrue,
      );
      expect(
        isLocationPermissionError(locationServicesDisabledMessage),
        isFalse,
      );
    });
  });

  group('isTransientLocationStreamError', () {
    test('matches the known iOS "no fix yet" failures, case-insensitively', () {
      const transient = <String>[
        'PlatformException(kCLErrorDomain error 1., null, null)',
        'kclerrordomain error 1',
        'Location update failure',
        'LOCATION UNKNOWN',
        'CLError.locationUnknown',
      ];

      for (final message in transient) {
        expect(
          isTransientLocationStreamError(message),
          isTrue,
          reason: 'expected "$message" to be treated as transient',
        );
      }
    });

    test('does not swallow genuine failures', () {
      expect(isTransientLocationStreamError('permission denied'), isFalse);
      expect(isTransientLocationStreamError(Exception('boom')), isFalse);
    });

    test('accepts any object, not just strings', () {
      expect(
        isTransientLocationStreamError(
          Exception('kCLErrorDomain error 1 while starting'),
        ),
        isTrue,
      );
    });
  });

  group('PositionSource defaults', () {
    test('seed and recovery positions default to null', () async {
      final source = _MinimalSource();

      expect(await source.getInitialPosition(), isNull);
      expect(await source.getRecoveryPosition(), isNull);
      expect(await source.ensureReady(), isNull);
      await expectLater(source.stream, emitsDone);
      await source.dispose();
    });
  });
}
