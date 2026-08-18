import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether the map screen draws real-world tiles behind the course.
///
/// Sailors on a metered connection — or out of range entirely — can turn the
/// basemap off and have it stay off next time.
class BasemapStore {
  static const _key = 'sail_race_basemap_enabled_v1';

  /// On by default: the chart background is what makes the course readable.
  Future<bool> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  Future<void> save({required bool enabled}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}
