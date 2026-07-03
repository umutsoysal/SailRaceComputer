import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/race_session_store.dart';
import '../utils/geo.dart';
import 'course_map_painter.dart';

class RecordingMapPreview extends StatelessWidget {
  const RecordingMapPreview({
    super.key,
    required this.entry,
    this.height = 148,
  });

  final RaceSessionEntry entry;
  final double height;

  List<LatLng> get _track => entry.record.track
      .map((point) => LatLng(point.latitude, point.longitude))
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final track = _track;
    final lastPoint =
        entry.record.track.isNotEmpty ? entry.record.track.last : null;
    final boat = track.isNotEmpty ? track.last : null;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFDCEBFA),
              borderRadius: BorderRadius.circular(18),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: CustomPaint(
                key: Key('recording-map-preview-${entry.id}'),
                painter: CourseMapPainter(
                  course: Course(name: '', buoys: const []),
                  boat: boat,
                  heading: lastPoint?.headingDeg ?? 0,
                  speedMs: lastPoint?.speedMs ?? 0,
                  track: track,
                  paddingPx: 24,
                  minSpanMeters: 80,
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: _PreviewBadge(
              icon: Icons.route_outlined,
              label:
                  '${entry.record.pointCount} pt${entry.record.pointCount == 1 ? '' : 's'}',
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: _PreviewBadge(
              icon: entry.record.completedCourse
                  ? Icons.flag
                  : Icons.pause_circle,
              label: entry.record.completedCourse ? 'Finished' : 'Saved early',
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.blueGrey.shade700),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
