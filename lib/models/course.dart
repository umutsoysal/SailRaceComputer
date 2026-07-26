import 'dart:convert';
import '../utils/geo.dart';

class Buoy {
  String name;
  LatLng position;

  /// Rounding radius in meters; entering this radius counts as rounded.
  double roundingRadiusM;

  Buoy({
    required this.name,
    required this.position,
    this.roundingRadiusM = 25.0,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'position': position.toJson(),
    'roundingRadiusM': roundingRadiusM,
  };

  factory Buoy.fromJson(Map<String, dynamic> j) => Buoy(
    name: j['name'] as String,
    position: LatLng.fromJson(j['position'] as Map<String, dynamic>),
    roundingRadiusM: (j['roundingRadiusM'] as num?)?.toDouble() ?? 25.0,
  );
}

class Course {
  String name;
  List<Buoy> buoys;

  Course({required this.name, required this.buoys});

  Map<String, dynamic> toJson() => {
    'name': name,
    'buoys': buoys.map((b) => b.toJson()).toList(),
  };

  factory Course.fromJson(Map<String, dynamic> j) => Course(
    name: j['name'] as String,
    buoys: (j['buoys'] as List<dynamic>)
        .map((b) => Buoy.fromJson(b as Map<String, dynamic>))
        .toList(),
  );

  String encode() => jsonEncode(toJson());
  static Course decode(String s) =>
      Course.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
