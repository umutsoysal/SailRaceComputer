import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sail_race_computer/models/course.dart';
import 'package:sail_race_computer/services/map_tiles.dart';
import 'package:sail_race_computer/utils/geo.dart';
import 'package:sail_race_computer/widgets/course_map_painter.dart';

const _sa7 = LatLng(41.852833, -87.556833);
const _mark1 = LatLng(41.871, -87.556833);
const _mark2 = LatLng(41.865667, -87.5395);

/// Maps degrees to canvas pixels 1:1 so expected offsets stay readable.
Offset _project(LatLng p) => Offset(p.lng * 10000, -p.lat * 10000);

Course _triangle() => Course(
  name: 'Triangle',
  buoys: [
    Buoy(name: 'SA7 Start/Finish', position: _sa7),
    Buoy(name: 'Mark 1', position: _mark1),
    Buoy(name: 'Mark 2', position: _mark2),
  ],
);

/// Stands in for the network tile loader: records what the painter looked up
/// and what it asked to be fetched, and hands back [image] for every lookup.
class _FakeTiles extends ChangeNotifier implements TileImageSource {
  _FakeTiles({this.image});

  final ui.Image? image;
  final asked = <TileCoord>[];
  final requested = <TileCoord>[];

  @override
  TileSource get source => TileSource.cartoLight;

  @override
  ui.Image? imageFor(TileCoord coord) {
    asked.add(coord);
    return image;
  }

  @override
  void request(Iterable<TileCoord> coords) => requested.addAll(coords);
}

Future<ui.Image> _tileImage() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 8, 8),
    Paint()..color = const Color(0xFF88AACC),
  );
  return recorder.endRecording().toImage(8, 8);
}

/// How many degrees of longitude a set of tiles spans in total.
double _lngSpanDegrees(List<TileCoord> tiles) {
  final west = tiles.map((t) => tileBounds(t).northWest.lng).reduce(math.min);
  final east = tiles.map((t) => tileBounds(t).southEast.lng).reduce(math.max);
  return east - west;
}

void _paint(CourseMapPainter painter, Size size) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  recorder.endRecording().dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('formats scale bar labels in nautical miles', () {
    expect(formatScaleBarNm(0.05), '0.05 NM');
    expect(formatScaleBarNm(0.5), '0.5 NM');
    expect(formatScaleBarNm(2), '2.0 NM');
    expect(formatScaleBarNm(10), '10 NM');
  });

  test('chooses a nice nautical mile scale bar near the target width', () {
    const pixelsPerMeter = 0.1;
    final choice = chooseScaleBarNm(
      pixelsPerMeter: pixelsPerMeter,
      targetWidthPx: 100,
    );

    expect(choice, anyOf(0.5, 1.0));
    final widthPx = choice * 1852.0 * pixelsPerMeter;
    expect(widthPx, greaterThanOrEqualTo(100));
    expect(widthPx, lessThan(220));
  });

  group('buoyLabelGroups', () {
    test('labels each distinct mark with its 1-based position', () {
      final course = Course(
        name: 'Triangle',
        buoys: [
          Buoy(name: 'SA7 Start/Finish', position: _sa7),
          Buoy(name: 'Mark 1', position: _mark1),
          Buoy(name: 'Mark 2', position: _mark2),
        ],
      );

      final groups = buoyLabelGroups(course, _project);

      expect(groups.map((g) => g.text), [
        '1. SA7 Start/Finish',
        '2. Mark 1',
        '3. Mark 2',
      ]);
      expect(groups.first.at, _project(_sa7));
    });

    test('merges marks that project onto the same point', () {
      final course = Course(
        name: 'Windward-leeward',
        buoys: [
          Buoy(name: 'SA7 Start/Finish', position: _sa7),
          Buoy(name: 'Mark 1', position: _mark1),
          Buoy(name: 'SA7 Finish', position: _sa7),
        ],
      );

      final groups = buoyLabelGroups(course, _project);

      expect(groups, hasLength(2));
      // The merged label keeps the first mark's name and lists both ordinals.
      expect(groups.first.text, '1·3. SA7 Start/Finish');
      expect(groups.last.text, '2. Mark 1');
    });

    test('merges marks that are merely close on screen', () {
      final course = Course(
        name: 'Gate',
        buoys: [
          Buoy(name: 'Gate', position: _sa7),
          Buoy(name: 'Gate pin', position: _sa7),
        ],
      );

      // Nudge the second projection 3px away — inside the default 6px radius.
      var call = 0;
      Offset project(LatLng p) =>
          _project(p) + (call++ == 0 ? Offset.zero : const Offset(3, 0));

      expect(buoyLabelGroups(course, project).single.text, '1·2. Gate');
    });

    test('keeps marks apart when they exceed the merge radius', () {
      final course = Course(
        name: 'Gate',
        buoys: [
          Buoy(name: 'Gate', position: _sa7),
          Buoy(name: 'Gate pin', position: _sa7),
        ],
      );

      var call = 0;
      Offset project(LatLng p) =>
          _project(p) + (call++ == 0 ? Offset.zero : const Offset(30, 0));

      final groups = buoyLabelGroups(course, project, mergeRadiusPx: 6);

      expect(groups.map((g) => g.text), ['1. Gate', '2. Gate pin']);
    });

    test('returns nothing for an empty course', () {
      final course = Course(name: 'Empty', buoys: []);

      expect(buoyLabelGroups(course, _project), isEmpty);
    });
  });

  group('CourseProjection', () {
    test('round-trips a position through the canvas and back', () {
      final proj = CourseProjection.fit(
        points: const [_sa7, _mark1, _mark2],
        size: const Size(800, 600),
        paddingPx: 48,
        minSpanMeters: 200,
      );

      final back = proj.toLatLng(proj.toCanvas(_mark2));

      expect(back.lat, closeTo(_mark2.lat, 1e-9));
      expect(back.lng, closeTo(_mark2.lng, 1e-9));
    });

    test('maps the canvas centre to the centre of the plotted points', () {
      final proj = CourseProjection.fit(
        points: const [_sa7, _mark1],
        size: const Size(800, 600),
        paddingPx: 48,
        minSpanMeters: 200,
      );

      final centre = proj.toLatLng(const Offset(400, 300));

      expect(centre.lat, closeTo((_sa7.lat + _mark1.lat) / 2, 1e-9));
      expect(centre.lng, closeTo(_sa7.lng, 1e-9));
    });
  });

  group('basemap tiles', () {
    const size = Size(800, 800);

    test('covers the course with tiles at one pyramid level', () {
      final tiles = _FakeTiles();

      _paint(
        CourseMapPainter(
          course: _triangle(),
          basemap: Basemap(tiles: tiles),
        ),
        size,
      );

      expect(tiles.asked, isNotEmpty);
      expect(tiles.asked.map((t) => t.z).toSet(), hasLength(1));
      // The mark in the middle of the course must be on one of them.
      final zoom = tiles.asked.first.z;
      expect(
        tiles.asked,
        contains(
          TileCoord(
            zoom,
            tileXForLng(_sa7.lng, zoom).floor(),
            tileYForLat(_sa7.lat, zoom).floor(),
          ),
        ),
      );
    });

    test('asks for the tiles it did not have', () {
      final tiles = _FakeTiles();

      _paint(
        CourseMapPainter(
          course: _triangle(),
          basemap: Basemap(tiles: tiles),
        ),
        size,
      );

      expect(tiles.requested, equals(tiles.asked));
    });

    test('refetches nothing once the tiles are cached', () async {
      final image = await _tileImage();
      addTearDown(image.dispose);
      final tiles = _FakeTiles(image: image);

      _paint(
        CourseMapPainter(
          course: _triangle(),
          basemap: Basemap(tiles: tiles),
        ),
        size,
      );

      expect(tiles.asked, isNotEmpty);
      expect(tiles.requested, isEmpty);
    });

    test('draws nothing extra when no basemap is configured', () {
      final tiles = _FakeTiles();

      _paint(CourseMapPainter(course: _triangle()), size);

      expect(tiles.asked, isEmpty);
    });

    test('zooms the tiles in with the interactive viewer', () {
      final wide = _FakeTiles();
      final zoomed = _FakeTiles();

      _paint(
        CourseMapPainter(
          course: _triangle(),
          basemap: Basemap(tiles: wide),
        ),
        size,
      );
      _paint(
        CourseMapPainter(
          course: _triangle(),
          // Four times the detail is two pyramid levels, given room for the
          // tiles that come with it.
          basemap: Basemap(tiles: zoomed, viewScale: 4, maxTiles: 256),
        ),
        size,
      );

      expect(zoomed.asked.first.z, wide.asked.first.z + 2);
    });

    test('only covers the visible slice of the canvas', () {
      final whole = _FakeTiles();
      final corner = _FakeTiles();

      _paint(
        CourseMapPainter(
          course: _triangle(),
          basemap: Basemap(tiles: whole),
        ),
        size,
      );
      _paint(
        CourseMapPainter(
          course: _triangle(),
          basemap: Basemap(
            tiles: corner,
            viewport: const Rect.fromLTWH(0, 0, 200, 200),
          ),
        ),
        size,
      );

      expect(corner.asked, isNotEmpty);
      expect(corner.asked.length, lessThan(whole.asked.length));
      expect(whole.asked, containsAll(corner.asked));
    });

    test('drops a pyramid level rather than blow the tile budget', () {
      final unbudgeted = _FakeTiles();
      final budgeted = _FakeTiles();

      _paint(
        CourseMapPainter(
          course: _triangle(),
          basemap: Basemap(tiles: unbudgeted, viewScale: 8),
        ),
        size,
      );
      _paint(
        CourseMapPainter(
          course: _triangle(),
          basemap: Basemap(tiles: budgeted, viewScale: 8, maxTiles: 4),
        ),
        size,
      );

      expect(budgeted.asked.length, lessThanOrEqualTo(4));
      expect(budgeted.asked.first.z, lessThan(unbudgeted.asked.first.z));
    });

    test('keeps drawing past the plot when the view is pulled back', () {
      final fitted = _FakeTiles();
      final pulledBack = _FakeTiles();

      _paint(
        CourseMapPainter(
          course: _triangle(),
          basemap: Basemap(tiles: fitted),
        ),
        size,
      );
      _paint(
        CourseMapPainter(
          course: _triangle(),
          // A quarter-scale view sees four canvases' worth in each direction.
          basemap: Basemap(
            tiles: pulledBack,
            viewScale: 0.25,
            viewport: const Rect.fromLTWH(-1200, -1200, 3200, 3200),
            maxTiles: 256,
          ),
        ),
        size,
      );

      // Same tile count at a coarser level, but a far wider slice of the world.
      expect(
        _lngSpanDegrees(pulledBack.asked),
        greaterThan(_lngSpanDegrees(fitted.asked) * 3),
      );
    });

    test('skips an empty viewport', () {
      final tiles = _FakeTiles();

      _paint(
        CourseMapPainter(
          course: _triangle(),
          basemap: Basemap(tiles: tiles, viewport: Rect.zero),
        ),
        size,
      );

      expect(tiles.asked, isEmpty);
    });
  });
}
