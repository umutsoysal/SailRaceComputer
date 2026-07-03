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

  /// Continuous stream of position fixes.
  Stream<Position> get stream;

  /// Tear down any resources.
  Future<void> dispose();
}

class GeolocatorPositionSource implements PositionSource {
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
