import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/course.dart';
import '../services/map_tiles.dart';
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
  final magnitude = math
      .pow(10, (math.log(targetNm) / math.ln10).floor())
      .toDouble();
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

/// One drawn buoy label: the canvas anchor plus the text to show there.
class BuoyLabelGroup {
  const BuoyLabelGroup({required this.at, required this.text});

  final Offset at;
  final String text;
}

/// Collapses buoys that project onto (near enough) the same canvas point into
/// a single label, so a start/finish mark rounded twice renders as
/// "1·5. SA7 Start/Finish" instead of two labels stacked on each other.
///
/// [toCanvas] projects a course position to canvas coordinates.
List<BuoyLabelGroup> buoyLabelGroups(
  Course course,
  Offset Function(LatLng) toCanvas, {
  double mergeRadiusPx = 6,
}) {
  final anchors = <Offset>[];
  final ordinals = <List<int>>[];
  final names = <String>[];

  for (var i = 0; i < course.buoys.length; i++) {
    final buoy = course.buoys[i];
    final at = toCanvas(buoy.position);
    final existing = anchors.indexWhere(
      (a) => (a - at).distance <= mergeRadiusPx,
    );
    if (existing >= 0) {
      ordinals[existing].add(i + 1);
    } else {
      anchors.add(at);
      ordinals.add(<int>[i + 1]);
      names.add(buoy.name);
    }
  }

  return <BuoyLabelGroup>[
    for (var i = 0; i < anchors.length; i++)
      BuoyLabelGroup(
        at: anchors[i],
        text: '${ordinals[i].join('·')}. ${names[i]}',
      ),
  ];
}

/// The real-world chart drawn behind a course: where the tiles come from and
/// how much of the canvas is actually on screen.
@immutable
class Basemap {
  const Basemap({
    required this.tiles,
    this.viewScale = 1,
    this.viewport,
    this.maxTiles = 64,
  });

  final TileImageSource tiles;

  /// Zoom factor the canvas is displayed at (the `InteractiveViewer` scale).
  /// Tiles are picked to match what the eye ends up seeing, not the untouched
  /// canvas.
  final double viewScale;

  /// The part of the canvas currently visible, in canvas pixels. Null covers
  /// the whole canvas.
  final Rect? viewport;

  /// Ceiling on tiles per frame. Hitting it drops a pyramid level rather than
  /// firing off hundreds of requests.
  final int maxTiles;

  @override
  bool operator ==(Object other) =>
      other is Basemap &&
      identical(other.tiles, tiles) &&
      other.viewScale == viewScale &&
      other.viewport == viewport &&
      other.maxTiles == maxTiles;

  @override
  int get hashCode => Object.hash(tiles, viewScale, viewport, maxTiles);
}

/// Top-down equirectangular projection of a course and optionally a boat
/// position.
///
/// [boat], [heading], [speedMs], and [track] are all optional; omit them to
/// render a static course overview with no boat overlay. Pass [basemap] to
/// draw real-world map tiles underneath; without it — or with no network —
/// the plain offline chart background is used instead.
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
    this.basemap,
  }) : super(repaint: basemap?.tiles);

  final Course course;
  final LatLng? boat;
  final double heading;
  final double speedMs;
  final List<LatLng> track;
  final int currentMarkIndex;
  final double paddingPx;
  final double minSpanMeters;
  final Basemap? basemap;

  late CourseProjection _proj;

  @override
  void paint(Canvas canvas, Size size) {
    final points = <LatLng>[
      ...course.buoys.map((b) => b.position),
      ?boat,
      ...track,
    ];
    _proj = CourseProjection.fit(
      points: points,
      size: size,
      paddingPx: paddingPx,
      minSpanMeters: minSpanMeters,
    );

    _drawBackground(canvas, size);
    final drewTiles = _drawBasemap(canvas, size);
    if (!drewTiles) _drawGrid(canvas, size);
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

  /// Blits the map tiles covering the visible canvas, and returns whether any
  /// were on hand. Missing tiles are requested for a later frame, so the first
  /// paint after opening the map draws nothing here and the chart background
  /// shows through until they arrive.
  bool _drawBasemap(Canvas canvas, Size size) {
    final map = basemap;
    if (map == null) return false;

    // Deliberately not clipped to the canvas: zoomed out, the viewport reaches
    // past the fitted course, and tiles out there are exactly the shoreline
    // and harbour the sailor pulled back to see.
    final view = map.viewport ?? Offset.zero & size;
    if (view.isEmpty || _proj.pixelsPerMeter <= 0) return false;

    final coords = _visibleTiles(map, view);
    if (coords.isEmpty) return false;

    final missing = <TileCoord>[];
    var drew = false;
    for (final coord in coords) {
      final image = map.tiles.imageFor(coord);
      if (image == null) {
        missing.add(coord);
        continue;
      }
      drew = _drawTile(canvas, image, coord) || drew;
    }
    if (missing.isNotEmpty) map.tiles.request(missing);
    return drew;
  }

  /// Tiles covering [view], at the pyramid level closest to what is on screen,
  /// stepping down a level at a time while the count exceeds the budget.
  List<TileCoord> _visibleTiles(Basemap map, Rect view) {
    final metersPerPixel = 1.0 / (_proj.pixelsPerMeter * map.viewScale);
    final source = map.tiles.source;
    var zoom = chooseTileZoom(
      metersPerPixel: metersPerPixel,
      latitude: _proj.centerLat,
      source: source,
    );

    while (true) {
      final coords = tilesForBounds(
        northWest: _proj.toLatLng(view.topLeft),
        southEast: _proj.toLatLng(view.bottomRight),
        zoom: zoom,
      );
      if (coords.length <= map.maxTiles || zoom <= source.minZoom) {
        return coords;
      }
      zoom--;
    }
  }

  bool _drawTile(Canvas canvas, ui.Image image, TileCoord coord) {
    final bounds = tileBounds(coord);
    final topLeft = _proj.toCanvas(bounds.northWest);
    final bottomRight = _proj.toCanvas(bounds.southEast);
    // Half a pixel of overlap: without it, rounding leaves hairline seams
    // between neighbouring tiles.
    final dst = Rect.fromPoints(topLeft, bottomRight).inflate(0.5);
    if (dst.isEmpty) return false;

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..isAntiAlias = true,
    );
    return true;
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
    }

    // Labels go on last so a later marker cannot paint over an earlier label.
    _drawBuoyLabels(canvas);
  }

  /// Labels every buoy, merging marks that share a position (a start/finish
  /// buoy rounded twice reads "1·5. SA7 Start/Finish") and nudging or dropping
  /// any label that would collide with one already drawn.
  void _drawBuoyLabels(Canvas canvas) {
    final placed = <Rect>[];
    for (final group in buoyLabelGroups(course, _proj.toCanvas)) {
      final tp = _labelPainter(group.text);
      final anchor = _placeLabel(tp, group.at, placed);
      if (anchor == null) continue;
      placed.add(_labelRect(tp, anchor));
      _paintLabel(canvas, tp, anchor);
    }
  }

  /// Picks the first candidate position around [at] whose label rect stays on
  /// canvas and clears [placed]. Returns null when every candidate collides,
  /// which drops the label rather than rendering unreadable overlap.
  Offset? _placeLabel(TextPainter tp, Offset at, List<Rect> placed) {
    final candidates = <Offset>[
      at + const Offset(12, -14),
      at + Offset(-tp.width - 12, -14),
      at + const Offset(12, 4),
      at + Offset(-tp.width - 12, 4),
      at + Offset(-tp.width / 2, -tp.height - 14),
      at + Offset(-tp.width / 2, 14),
    ];
    for (final candidate in candidates) {
      final rect = _labelRect(tp, candidate);
      if (rect.left < 0 ||
          rect.top < 0 ||
          rect.right > _proj.size.width ||
          rect.bottom > _proj.size.height) {
        continue;
      }
      if (placed.any(rect.overlaps)) continue;
      return candidate;
    }
    return null;
  }

  static Rect _labelRect(TextPainter tp, Offset at) =>
      Rect.fromLTWH(at.dx - 3, at.dy - 1, tp.width + 6, tp.height + 2);

  static TextPainter _labelPainter(String text) => TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(
        color: Colors.black87,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  void _paintLabel(Canvas canvas, TextPainter tp, Offset at) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(_labelRect(tp, at), const Radius.circular(3)),
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
    tp.paint(canvas, at);
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
    Canvas canvas,
    Offset tip,
    double headingDeg,
    Color color,
  ) {
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

  void _label(Canvas canvas, String text, Offset at) =>
      _paintLabel(canvas, _labelPainter(text), at);

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
          m.extractPath(d, math.min(d + dash, m.length)),
          Offset.zero,
        );
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
      old.currentMarkIndex != currentMarkIndex ||
      old.basemap != basemap;
}

/// Equirectangular projection about the centre of the plotted points: metres
/// east/north of the centre, scaled to canvas pixels.
class CourseProjection {
  CourseProjection({
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

  factory CourseProjection.fit({
    required List<LatLng> points,
    required Size size,
    required double paddingPx,
    required double minSpanMeters,
  }) {
    if (points.isEmpty) {
      return CourseProjection(
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
    final metersPerDegLng = 111320.0 * math.cos(centerLat * math.pi / 180.0);

    var spanMetersX = math.max(
      (maxLng - minLng) * metersPerDegLng,
      minSpanMeters,
    );
    var spanMetersY = math.max(
      (maxLat - minLat) * metersPerDegLat,
      minSpanMeters,
    );
    if (spanMetersX == 0) spanMetersX = minSpanMeters;
    if (spanMetersY == 0) spanMetersY = minSpanMeters;

    final usableW = math.max(1.0, size.width - 2 * paddingPx);
    final usableH = math.max(1.0, size.height - 2 * paddingPx);
    final pxPerMeter = math.min(usableW / spanMetersX, usableH / spanMetersY);

    return CourseProjection(
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

  /// Inverse of [toCanvas].
  LatLng toLatLng(Offset p) {
    if (pixelsPerMeter <= 0) return LatLng(centerLat, centerLng);
    final dxMeters = (p.dx - size.width / 2) / pixelsPerMeter;
    final dyMeters = (size.height / 2 - p.dy) / pixelsPerMeter;
    return LatLng(
      centerLat + dyMeters / metersPerDegLat,
      centerLng + (metersPerDegLng == 0 ? 0 : dxMeters / metersPerDegLng),
    );
  }
}
