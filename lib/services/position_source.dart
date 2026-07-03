import 'dart:async';
import 'package:geolocator/geolocator.dart';

const locationServicesDisabledMessage = 'Location services are disabled.';
const locationPermissionDeniedMessage =
    'Location permission denied. Enable location access for Race Mate in Settings.';
const locationPermissionDeniedForeverMessage =
    'Location permission denied forever. Enable location access for Race Mate in Settings.';

bool isLocationServicesDisabledError(String error) =>
    error == locationServicesDisabledMessage;

bool isLocationPermissionError(String error) =>
    error == locationPermissionDeniedMessage ||
    error == locationPermissionDeniedForeverMessage;

/// Abstraction over "where do position fixes come from" so the production app
/// can use real GPS and the dev simulator can inject a fake stream.
abstract class PositionSource {
  /// Initialize permissions / services. Returns null on success or a
  /// human-readable error message on failure.
  Future<String?> ensureReady();

  /// Best-effort initial position used to seed the UI while the live stream
  /// is still warming up. Returns null when no reasonable initial fix exists.
  Future<Position?> getInitialPosition() async => null;

  /// Best-effort one-shot position sample used when the live stream has gone
  /// quiet and the UI wants to verify whether GPS is actually unavailable.
  Future<Position?> getRecoveryPosition() async => null;

  /// Continuous stream of position fixes.
  Stream<Position> get stream;

  /// Tear down any resources.
  Future<void> dispose();
}

class GeolocatorPositionSource implements PositionSource {
  static const _maxSeedAge = Duration(seconds: 10);
  static const _maxRecoveryAge = Duration(seconds: 3);

  StreamSubscription<Position>? _sub;
  StreamController<Position>? _ctrl;

  @override
  Future<String?> ensureReady() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return locationServicesDisabledMessage;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      return locationPermissionDeniedMessage;
    }
    if (perm == LocationPermission.deniedForever) {
      return locationPermissionDeniedForeverMessage;
    }
    return null;
  }

  // Both methods below intentionally read only the OS-cached position and
  // never call getCurrentPosition: a one-shot high-accuracy request issued
  // while the live stream is warming up competes with it for the GPS radio
  // (and on iOS its errors leak into the stream's error handler), which
  // delays or breaks first-fix acquisition.
  @override
  Future<Position?> getInitialPosition() => _freshLastKnown(_maxSeedAge);

  @override
  Future<Position?> getRecoveryPosition() => _freshLastKnown(_maxRecoveryAge);

  Future<Position?> _freshLastKnown(Duration maxAge) async {
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown == null) return null;
      final age = DateTime.now().toUtc().difference(
        lastKnown.timestamp.toUtc(),
      );
      return age <= maxAge ? lastKnown : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<Position> get stream {
    final c = _ctrl ??= StreamController<Position>.broadcast(
      onCancel: () => _sub?.pause(),
      onListen: () => _sub?.resume(),
    );
    _sub ??= Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen(c.add, onError: c.addError);
    return c.stream;
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    await _ctrl?.close();
    _sub = null;
    _ctrl = null;
  }
}
