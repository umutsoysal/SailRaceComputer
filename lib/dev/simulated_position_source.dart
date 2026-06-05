import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../services/position_source.dart';
import 'boat_simulator.dart';

/// Adapts a [BoatSimulator] to the [PositionSource] interface so the real
/// production `RaceScreen` can be driven by the on-desk simulator.
class SimulatedPositionSource implements PositionSource {
  SimulatedPositionSource(this.sim);

  final BoatSimulator sim;
  final _ctrl = StreamController<Position>.broadcast();
  VoidCallback? _listener;

  @override
  Future<String?> ensureReady() async => null;

  @override
  Stream<Position> get stream {
    _listener ??= () {
      _ctrl.add(Position(
        longitude: sim.position.lng,
        latitude: sim.position.lat,
        timestamp: DateTime.now(),
        accuracy: 3.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: sim.headingDeg,
        headingAccuracy: 0.0,
        speed: sim.speedMs,
        speedAccuracy: 0.0,
        isMocked: true,
      ));
    };
    sim.addListener(_listener!);
    // Emit one fix right away so the consumer doesn't sit on a spinner.
    scheduleMicrotask(_listener!);
    return _ctrl.stream;
  }

  @override
  Future<void> dispose() async {
    if (_listener != null) sim.removeListener(_listener!);
    await _ctrl.close();
  }
}
