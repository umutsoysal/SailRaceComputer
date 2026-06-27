import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utils/geo.dart';

/// Headless boat simulator. Advances position from (heading, speed) at 5 Hz
/// and keeps a short track trail. Used only by the dev simulator entrypoint.
class BoatSimulator extends ChangeNotifier {
  BoatSimulator({
    required LatLng startPosition,
    double headingDeg = 0,
    double speedKnots = 5,
  })  : _position = startPosition,
        _headingDeg = headingDeg,
        _speedKnots = speedKnots;

  LatLng _position;
  double _headingDeg;
  double _speedKnots;
  bool _running = false;
  Timer? _timer;
  final List<LatLng> _track = [];

  static const _tickMs = 200; // 5 Hz
  static const _maxTrack = 600; // ~2 min of trail

  LatLng get position => _position;
  double get headingDeg => _headingDeg;
  double get speedKnots => _speedKnots;
  double get speedMs => knotsToMs(_speedKnots);
  bool get running => _running;
  List<LatLng> get track => List.unmodifiable(_track);

  void start() {
    if (_running) return;
    _running = true;
    _timer =
        Timer.periodic(const Duration(milliseconds: _tickMs), (_) => _tick());
    notifyListeners();
  }

  void pause() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  void toggle() => _running ? pause() : start();

  void reset(LatLng to) {
    pause();
    _position = to;
    _track.clear();
    notifyListeners();
  }

  void setHeading(double deg) {
    _headingDeg = (deg % 360 + 360) % 360;
    notifyListeners();
  }

  void setSpeed(double knots) {
    _speedKnots = knots.clamp(0, 30).toDouble();
    notifyListeners();
  }

  /// Teleport the boat without clearing the trail.
  void teleport(LatLng to) {
    _position = to;
    notifyListeners();
  }

  void _tick() {
    final dtSec = _tickMs / 1000.0;
    final dM = speedMs * dtSec;
    if (dM > 0) {
      _position = destinationPoint(_position, dM, _headingDeg);
      _track.add(_position);
      if (_track.length > _maxTrack) {
        _track.removeRange(0, _track.length - _maxTrack);
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
