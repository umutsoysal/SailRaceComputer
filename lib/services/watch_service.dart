import 'package:flutter/services.dart';

class WatchService {
  static const _channel = MethodChannel('sail_race/watch');

  static Future<void> sendMetrics({
    required double vmgKnots,
    required double distanceNM,
    required double bearing,
    required double sogKnots,
    required double cogDegrees,
    required String markName,
    required int markIndex,
    required int markTotal,
    String? eta,
  }) async {
    try {
      await _channel.invokeMethod('sendMetrics', {
        'vmg': vmgKnots,
        'distance': distanceNM,
        'bearing': bearing,
        'sog': sogKnots,
        'cog': cogDegrees,
        'markName': markName,
        'markIndex': markIndex,
        'markTotal': markTotal,
        'eta': eta,
      });
    } catch (_) {
      // Watch not paired, not reachable, or running on Android — ignore silently.
    }
  }
}
