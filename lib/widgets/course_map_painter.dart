import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/course.dart';
import '../utils/geo.dart';

double chooseScaleBarNm({
  required double pixelsPerMeter,
  required double targetWidthPx,
}) {
  final pixelsPerNm = pixelsPerMeter * 1852.0;
  if (pixelsPerNm <= 0 || targetWidthPx <= 0) {
    return 0.1;
  }

  final targetNm = targetWidthPx / pixelsPerNm;
  final magnitude =
      math.pow(10, (math.log(targetNm) / math.ln10).floor()).toDouble();
  final base = magnitude > 0 ? magnitude : 0.01;

  for (final factor in const [1.0, 2.0, 5.0, 10.0]) {
    final candidate = base * factor;
    if (candidate >= targetNm) {
      return candidate;
    }
  }

  return base * 10.0;
}

String formatScaleBarNm(double nm) {
  if (nm >= 10) return '${nm.toStringAsFixed(0)} NM';
  if (nm >= 1) return '${nm.toStringAsFixed(1)} NM';
  if (nm >= 0.1) return '${nm.toStringAsFixed(1)} NM';
  return '${nm.toStringAsFixed(2)} NM';
}

/// Top-down equirectangular projection of a course and optionally a boat
/// position. Pure CustomPainter — no map tiles, works offline.
///
/// [boat], [heading], [speedMs], and [track] are all optional; omit them to
/// render a static course overview with no boat overlay.
class CourseMapPainter extends CustomPainter {
  CourseMapPainter({
    required this.course,
    this.boat,
    this.heading = 0,
    this.speedMs = 0,
    this.track = const [],
    this.currentMarkIndex = 0,
    this.paddingPx = 48,
    this.minSpanMeters = 200,
  });

  final Course course;
  final LatLng? boat;
  final double heading;
  final double speedMs;
  final List<LatLng> track;
  final int currentMarkIndex;
  final double paddingPx;
  final double minSpanMeters;

  late _Projection _proj;

  @override
  void paint(Canvas canvas, Size size) {
    final points = [
      ...course.buoys.map((b) => b.position),
      ?boat,
      ...track,
    ];
    _proj = _Projection.fit(
      points: points,
      size: size,
      paddingPx: paddingPx,
      minSpanMeters: minSpanMeters,
    );

    _drawBackground(canvas, size);
    _drawGrid(canvas, size);
    _drawCourseLines(canvas);
    _drawTrack(canvas);
    _drawBuoys(canvas);
    if (boat != null) _drawBoat(canvas);
    _drawScaleBar(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFEAF3FA);
    canvas.drawRect(Offset.zero & size, paint);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;
    const step = 60.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  void _drawCourseLines(Canvas canvas) {
    if (course.buoys.length < 2) return;
    final p = Paint()
      ..color = Colors.blueGrey.shade400
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    final first = _proj.toCanvas(course.buoys.first.position);
    path.moveTo(first.dx, first.dy);
    for (var i = 1; i < course.buoys.length; i++) {
      final pt = _proj.toCanvas(course.buoys[i].position);
      path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(_dashed(path, 8, 6), p);
  }

  void _drawTrack(Canvas canvas) {
    if (track.length < 2) return;
    final p = Paint()
      ..color = Colors.deepOrange.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    final first = _proj.toCanvas(track.first);
    path.moveTo(first.dx, first.dy);
    for (var i = 1; i < track.length; i++) {
      final pt = _proj.toCanvas(track[i]);
      path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(path, p);
  }

  void _drawBuoys(Canvas canvas) {
    for (var i = 0; i < course.buoys.length; i++) {
      final b = course.buoys[i];
      final c = _proj.toCanvas(b.position);
      final isCurrent = i == currentMarkIndex;
      final color = isCurrent ? Colors.green.shade700 : Colors.blueGrey;

      // rounding circle
      final radiusPx = _proj.metersToPixels(b.roundingRadiusM);
      canvas.drawCircle(
        c,
        radiusPx,
        Paint()
          ..color = color.withValues(alpha: 0.15)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        c,
        radiusPx,
        Paint()
          ..color = color.withValues(alpha: 0.6)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );

      // buoy marker
      canvas.drawCircle(c, 8, Paint()..color = color);
      canvas.drawCircle(
        c,
        8,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );

      _label(canvas, '${i + 1}. ${b.name}', c + const Offset(12, -14));
    }
  }

  void _drawBoat(Canvas canvas) {
    final b = boat;
    if (b == null) return;
    final c = _proj.toCanvas(b);

    // velocity vector
    if (speedMs > 0.05) {
      final lenPx = math.min(120.0, speedMs * 1.9438 * 6.0);
      final rad = (heading - 90) * math.pi / 180.0;
      final end = c + Offset(math.cos(rad) * lenPx, math.sin(rad) * lenPx);
      final p = Paint()
        ..color = Colors.red
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      canvas.drawLine(c, end, p);
      _drawArrowHead(canvas, end, heading, Colors.red);
    }

    // boat triangle, pointing along heading
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(heading * math.pi / 180.0);
    final path = Path()
      ..moveTo(0, -14)
      ..lineTo(9, 10)
      ..lineTo(0, 6)
      ..lineTo(-9, 10)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.indigo.shade700);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
    canvas.restore();
  }

  void _drawArrowHead(
      Canvas canvas, Offset tip, double headingDeg, Color color) {
    final rad = (headingDeg - 90) * math.pi / 180.0;
    final left =
        tip + Offset(math.cos(rad + 2.6) * 10, math.sin(rad + 2.6) * 10);
    final right =
        tip + Offset(math.cos(rad - 2.6) * 10, math.sin(rad - 2.6) * 10);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _label(Canvas canvas, String text, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
            color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final bg = Rect.fromLTWH(
        at.dx - 3, at.dy - 1, tp.width + 6, tp.height + 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bg, const Radius.circular(3)),
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
    tp.paint(canvas, at);
  }

  void _drawScaleBar(Canvas canvas, Size size) {
    final targetWidthPx = math.min(120.0, size.width * 0.22);
    final niceNm = chooseScaleBarNm(
      pixelsPerMeter: _proj.pixelsPerMeter,
      targetWidthPx: targetWidthPx,
    );
    final widthPx = _proj.metersToPixels(niceNm * 1852.0);
    final y = size.height - 24;
    const x = 16.0;
    final p = Paint()
      ..color = Colors.black87
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x, y), Offset(x + widthPx, y), p);
    canvas.drawLine(Offset(x, y - 4), Offset(x, y + 4), p);
    canvas.drawLine(Offset(x + widthPx, y - 4), Offset(x + widthPx, y + 4), p);
    _label(canvas, formatScaleBarNm(niceNm), Offset(x + widthPx + 6, y - 8));
  }

  Path _dashed(Path src, double dash, double gap) {
    final out = Path();
    for (final m in src.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        out.addPath(
            m.extractPath(d, math.min(d + dash, m.length)), Offset.zero);
        d += dash + gap;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant CourseMapPainter old) =>
      old.course != course ||
      old.boat != boat ||
      old.heading != heading ||
      old.speedMs != speedMs ||
      old.track.length != track.length ||
      old.currentMarkIndex != currentMarkIndex;
}

class _Projection {
  _Projection({
    required this.centerLat,
    required this.centerLng,
    required this.metersPerDegLat,
    required this.metersPerDegLng,
    required this.pixelsPerMeter,
    required this.size,
  });

  final double centerLat;
  final double centerLng;
  final double metersPerDegLat;
  final double metersPerDegLng;
  final double pixelsPerMeter;
  final Size size;

  factory _Projection.fit({
    required List<LatLng> points,
    required Size size,
    required double paddingPx,
    required double minSpanMeters,
  }) {
    if (points.isEmpty) {
      return _Projection(
        centerLat: 0,
        centerLng: 0,
        metersPerDegLat: 111320,
        metersPerDegLng: 111320,
        pixelsPerMeter: 1,
        size: size,
      );
    }
    double minLat = points.first.lat, maxLat = points.first.lat;
    double minLng = points.first.lng, maxLng = points.first.lng;
    for (final p in points) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }
    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;
    const metersPerDegLat = 111320.0;
    final metersPerDegLng =
        111320.0 * math.cos(centerLat * math.pi / 180.0);

    var spanMetersX =
        math.max((maxLng - minLng) * metersPerDegLng, minSpanMeters);
    var spanMetersY =
        math.max((maxLat - minLat) * metersPerDegLat, minSpanMeters);
    if (spanMetersX == 0) spanMetersX = minSpanMeters;
    if (spanMetersY == 0) spanMetersY = minSpanMeters;

    final usableW = math.max(1.0, size.width - 2 * paddingPx);
    final usableH = math.max(1.0, size.height - 2 * paddingPx);
    final pxPerMeter = math.min(usableW / spanMetersX, usableH / spanMetersY);

    return _Projection(
      centerLat: centerLat,
      centerLng: centerLng,
      metersPerDegLat: metersPerDegLat,
      metersPerDegLng: metersPerDegLng,
      pixelsPerMeter: pxPerMeter,
      size: size,
    );
  }

  double metersToPixels(double m) => m * pixelsPerMeter;

  Offset toCanvas(LatLng p) {
    final dxMeters = (p.lng - centerLng) * metersPerDegLng;
    final dyMeters = (p.lat - centerLat) * metersPerDegLat;
    return Offset(
      size.width / 2 + dxMeters * pixelsPerMeter,
      size.height / 2 - dyMeters * pixelsPerMeter,
    );
  }
}
