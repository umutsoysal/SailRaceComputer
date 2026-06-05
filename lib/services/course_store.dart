import 'package:shared_preferences/shared_preferences.dart';
import '../models/course.dart';

class CourseStore {
  static const _key = 'sail_race_course_v1';

  Future<Course?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_key);
    if (s == null || s.isEmpty) return null;
    try {
      return Course.decode(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Course course) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, course.encode());
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
