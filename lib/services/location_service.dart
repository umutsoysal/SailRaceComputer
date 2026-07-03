import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'position_source.dart';

class LocationService extends ChangeNotifier {
  LocationService({
    PositionSource? positionSource,
    this.signalTimeout = const Duration(seconds: 8),
  })  : _source = positionSource ?? GeolocatorPositionSource(),
        _ownsSource = positionSource == null;

  final PositionSource _source;
  final bool _ownsSource;
  final Duration signalTimeout;

  StreamSubscription<Position>? _sub;
  Timer? _signalTimer;
  Position? _position;
  String? _error;
  bool _isActive = false;
  bool _isPaused = false;
  bool _hasReceivedFix = false;
  bool _showNoSignal = false;
  bool _recoveryInFlight = false;
  bool _disposed = false;
  int _sessionId = 0;
  int _fixVersion = 0;

  Position? get position => _position;
  String? get error => _error;
  bool get hasReceivedFix => _hasReceivedFix;
  bool get showNoSignal => _showNoSignal;
  bool get isActive => _isActive;
  bool get isPaused => _isPaused;
  bool get isAcquiring =>
      _isActive && !_isPaused && _error == null && !_hasReceivedFix;
  int get fixVersion => _fixVersion;

  Future<String?> start({bool resetPosition = true}) async {
    final sessionId = ++_sessionId;
    await _cancelTracking();
    _isActive = true;
    _isPaused = false;
    _error = null;
    _showNoSignal = false;
    _recoveryInFlight = false;
    if (resetPosition) {
      _position = null;
      _hasReceivedFix = false;
    }
    _notify();

    final err = await _source.ensureReady();
    if (_disposed || sessionId != _sessionId) return err;
    if (err != null) {
      _isActive = false;
      _error = err;
      _notify();
      return err;
    }

    _sub = _source.stream.listen(
      _handleFix,
      onError: (error) {
        if (_disposed || !_isActive) return;
        if (isTransientLocationStreamError(error)) return;
        _error = error.toString();
        _showNoSignal = false;
        _notify();
      },
    );
    _armSignalTimeout(sessionId);
    unawaited(_primeInitialFix(sessionId));
    return null;
  }

  void pause() {
    if (!_isActive || _isPaused) return;
    _sub?.pause();
    _signalTimer?.cancel();
    _isPaused = true;
    _error = null;
    _showNoSignal = false;
    _notify();
  }

  void resume() {
    if (!_isActive || !_isPaused) return;
    _sub?.resume();
    _isPaused = false;
    _error = null;
    _showNoSignal = false;
    _armSignalTimeout(_sessionId);
    _notify();
  }

  Future<void> stop({
    bool clearError = false,
    bool clearPosition = false,
  }) async {
    _sessionId++;
    await _cancelTracking();
    _isActive = false;
    _isPaused = false;
    _showNoSignal = false;
    _recoveryInFlight = false;
    if (clearError) _error = null;
    if (clearPosition) {
      _position = null;
      _hasReceivedFix = false;
    }
    _notify();
  }

  Future<void> _primeInitialFix(int sessionId) async {
    try {
      final initial = await _source.getInitialPosition();
      if (_disposed || sessionId != _sessionId || initial == null) return;
      if (!_isActive || _isPaused || _hasReceivedFix) return;
      _applyFix(initial, sessionId);
    } catch (_) {
      // Best-effort only. The live stream remains the source of truth.
    }
  }

  void _handleFix(Position position) {
    _applyFix(position, _sessionId);
  }

  void _applyFix(Position position, int sessionId) {
    if (_disposed || sessionId != _sessionId) return;
    if (!_isActive) return;
    _position = position;
    _error = null;
    _hasReceivedFix = true;
    _showNoSignal = false;
    _fixVersion++;
    if (!_isPaused) {
      _armSignalTimeout(sessionId);
    }
    _notify();
  }

  void _armSignalTimeout(int sessionId) {
    _signalTimer?.cancel();
    _signalTimer = Timer(signalTimeout, () {
      if (_disposed || sessionId != _sessionId) return;
      if (!_isActive || _isPaused || _error != null) return;
      unawaited(_attemptRecoveryAfterTimeout(sessionId));
    });
  }

  Future<void> _attemptRecoveryAfterTimeout(int sessionId) async {
    if (_recoveryInFlight) return;
    _recoveryInFlight = true;
    try {
      final sampled = await _source.getRecoveryPosition();
      if (_disposed || sessionId != _sessionId) return;
      if (!_isActive || _isPaused || _error != null) return;
      if (sampled != null) {
        _applyFix(sampled, sessionId);
        return;
      }
      if (_hasReceivedFix) {
        _showNoSignal = true;
        _notify();
      } else {
        _armSignalTimeout(sessionId);
      }
    } finally {
      _recoveryInFlight = false;
    }
  }

  Future<void> _cancelTracking() async {
    _signalTimer?.cancel();
    _signalTimer = null;
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _signalTimer?.cancel();
    unawaited(_sub?.cancel());
    if (_ownsSource) {
      unawaited(_source.dispose());
    }
    super.dispose();
  }
}
