import 'package:flutter_test/flutter_test.dart';

import 'package:sail_race_computer/services/map_tiles.dart';
import 'package:sail_race_computer/utils/geo.dart';

const _chicago = LatLng(41.852833, -87.556833);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tile addressing', () {
    test('builds tile urls, with the retina suffix only when asked', () {
      const coord = TileCoord(16, 16819, 24427);

      expect(
        TileSource.cartoLight.urlFor(coord),
        'https://basemaps.cartocdn.com/light_all/16/16819/24427.png',
      );
      expect(
        TileSource.cartoLight.urlFor(coord, retina: true),
        'https://basemaps.cartocdn.com/light_all/16/16819/24427@2x.png',
      );
    });

    test('treats the same z/x/y as the same tile', () {
      expect(const TileCoord(16, 1, 2), const TileCoord(16, 1, 2));
      expect(
        const TileCoord(16, 1, 2).hashCode,
        const TileCoord(16, 1, 2).hashCode,
      );
      expect(const TileCoord(16, 1, 2), isNot(const TileCoord(15, 1, 2)));
    });

    test('wraps the whole world in one tile at zoom 0', () {
      expect(tileXForLng(-180, 0), closeTo(0, 1e-9));
      expect(tileXForLng(180, 0), closeTo(1, 1e-9));
      expect(tileYForLat(0, 0), closeTo(0.5, 1e-9));
    });

    test('round-trips a position through tile coordinates', () {
      const zoom = 16;
      final x = tileXForLng(_chicago.lng, zoom);
      final y = tileYForLat(_chicago.lat, zoom);

      expect(lngForTileX(x, zoom), closeTo(_chicago.lng, 1e-9));
      expect(latForTileY(y, zoom), closeTo(_chicago.lat, 1e-9));
    });

    test('bounds of a tile contain the position that addressed it', () {
      const zoom = 14;
      final coord = TileCoord(
        zoom,
        tileXForLng(_chicago.lng, zoom).floor(),
        tileYForLat(_chicago.lat, zoom).floor(),
      );

      final bounds = tileBounds(coord);

      expect(bounds.northWest.lat, greaterThan(_chicago.lat));
      expect(bounds.southEast.lat, lessThan(_chicago.lat));
      expect(bounds.northWest.lng, lessThan(_chicago.lng));
      expect(bounds.southEast.lng, greaterThan(_chicago.lng));
    });
  });

  group('chooseTileZoom', () {
    test('matches the pyramid level to the on-screen resolution', () {
      for (final zoom in const [10, 14, 17]) {
        final metersPerPixel = tileResolutionMeters(zoom, _chicago.lat);

        expect(
          chooseTileZoom(
            metersPerPixel: metersPerPixel,
            latitude: _chicago.lat,
          ),
          zoom,
        );
      }
    });

    test('zooms in as the view gets finer', () {
      final wide = chooseTileZoom(metersPerPixel: 40, latitude: _chicago.lat);
      final tight = chooseTileZoom(metersPerPixel: 2.5, latitude: _chicago.lat);

      expect(tight, greaterThan(wide));
    });

    test('clamps to what the source serves', () {
      expect(
        chooseTileZoom(metersPerPixel: 0.001, latitude: _chicago.lat),
        TileSource.cartoLight.maxZoom,
      );
      expect(
        chooseTileZoom(metersPerPixel: 1e9, latitude: _chicago.lat),
        TileSource.cartoLight.minZoom,
      );
      expect(
        chooseTileZoom(metersPerPixel: 0, latitude: _chicago.lat),
        TileSource.cartoLight.maxZoom,
      );
    });
  });

  group('tilesForBounds', () {
    test('returns the single tile a small course falls inside', () {
      const zoom = 12;
      final tiles = tilesForBounds(
        northWest: const LatLng(41.86, -87.56),
        southEast: const LatLng(41.855, -87.555),
        zoom: zoom,
      );

      expect(tiles, hasLength(1));
      expect(tiles.single.z, zoom);
      expect(tiles.single.x, tileXForLng(-87.56, zoom).floor());
    });

    test('covers every tile the bounds touch', () {
      const zoom = 14;
      final tiles = tilesForBounds(
        northWest: const LatLng(41.92, -87.65),
        southEast: const LatLng(41.80, -87.50),
        zoom: zoom,
      );

      final columns = tiles.map((t) => t.x).toSet();
      final rows = tiles.map((t) => t.y).toSet();

      expect(tiles, hasLength(columns.length * rows.length));
      expect(columns.length, greaterThan(1));
      expect(rows.length, greaterThan(1));
      // Contiguous, no gaps.
      expect(
        columns.reduce((a, b) => a > b ? a : b) -
            columns.reduce((a, b) => a < b ? a : b),
        columns.length - 1,
      );
    });

    test('grows fourfold per pyramid level', () {
      const northWest = LatLng(41.90, -87.62);
      const southEast = LatLng(41.84, -87.54);

      final coarse = tilesForBounds(
        northWest: northWest,
        southEast: southEast,
        zoom: 13,
      );
      final fine = tilesForBounds(
        northWest: northWest,
        southEast: southEast,
        zoom: 15,
      );

      expect(fine.length, greaterThan(coarse.length * 8));
    });

    test('returns nothing for inverted bounds', () {
      expect(
        tilesForBounds(
          northWest: const LatLng(41.80, -87.50),
          southEast: const LatLng(41.92, -87.65),
          zoom: 14,
        ),
        isEmpty,
      );
    });
  });

  group('MapTileLoader', () {
    test('has no tile until one has been fetched', () {
      final loader = MapTileLoader();
      addTearDown(loader.dispose);

      expect(loader.imageFor(const TileCoord(14, 1, 1)), isNull);
    });

    test('remembers failures instead of refetching them every frame', () async {
      // flutter_test serves 400 for every image request, so this exercises the
      // offline path: the map keeps its plain chart background.
      final loader = MapTileLoader();
      addTearDown(loader.dispose);
      const coord = TileCoord(14, 4194, 6096);

      loader.request(const [coord]);
      await pumpEventQueue();

      expect(loader.failureCount, 1);
      expect(loader.imageFor(coord), isNull);

      loader.request(const [coord]);
      await pumpEventQueue();

      expect(loader.failureCount, 1);
    });

    test('ignores requests after disposal', () async {
      final loader = MapTileLoader()..dispose();

      loader.request(const [TileCoord(14, 1, 1)]);
      await pumpEventQueue();

      expect(loader.failureCount, 0);
    });
  });
}
