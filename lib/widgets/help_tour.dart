import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One step of the overlay help tour.
///
/// When [targetKey] is null the card is centered with a plain scrim (used for
/// the welcome step); otherwise the target widget is spotlighted.
class HelpTourStep {
  const HelpTourStep({required this.title, required this.body, this.targetKey});

  final String title;
  final String body;
  final GlobalKey? targetKey;
}

/// A lightweight spotlight walkthrough drawn on the app's root overlay.
///
/// Shown once on first launch (persisted via [SharedPreferences]) and
/// replayable from Settings.
class HelpTour {
  HelpTour._();

  static const _seenPrefKey = 'help_tour_seen_v1';
  static OverlayEntry? _entry;

  /// Whether the tour has been completed or dismissed before. Errs on the
  /// side of `true` so a prefs failure never traps the user in the tour.
  static Future<bool> hasSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_seenPrefKey) ?? false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> _markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_seenPrefKey, true);
    } catch (_) {}
  }

  /// Shows the tour unless one is already visible.
  ///
  /// [onStepShown] fires with the step index whenever a step appears, so the
  /// caller can e.g. switch the active tab to match the highlighted item.
  static void show(
    BuildContext context, {
    required List<HelpTourStep> steps,
    ValueChanged<int>? onStepShown,
  }) {
    if (_entry != null || steps.isEmpty) return;
    final entry = OverlayEntry(
      builder: (_) => _HelpTourOverlay(
        steps: steps,
        onStepShown: onStepShown,
        onFinished: dismiss,
      ),
    );
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  static void dismiss() {
    _entry?.remove();
    _entry = null;
    _markSeen();
  }
}

class _HelpTourOverlay extends StatefulWidget {
  const _HelpTourOverlay({
    required this.steps,
    required this.onFinished,
    this.onStepShown,
  });

  final List<HelpTourStep> steps;
  final VoidCallback onFinished;
  final ValueChanged<int>? onStepShown;

  @override
  State<_HelpTourOverlay> createState() => _HelpTourOverlayState();
}

class _HelpTourOverlayState extends State<_HelpTourOverlay> {
  var _index = 0;
  Rect? _targetRect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onStepShown?.call(0);
      _measureTarget();
    });
  }

  void _goTo(int index) {
    if (index < 0) return;
    if (index >= widget.steps.length) {
      widget.onFinished();
      return;
    }
    setState(() {
      _index = index;
      _targetRect = null;
    });
    widget.onStepShown?.call(index);
    // Measure after the frame so any tab switch triggered by onStepShown has
    // settled before the spotlight is placed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureTarget());
  }

  void _measureTarget() {
    if (!mounted) return;
    final renderObject = widget.steps[_index].targetKey?.currentContext
        ?.findRenderObject();
    Rect? rect;
    if (renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize) {
      rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    }
    setState(() => _targetRect = rect);
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_index];
    final screen = MediaQuery.sizeOf(context);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _goTo(_index + 1),
            child: CustomPaint(
              painter: _SpotlightPainter(
                target: _targetRect,
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
        _positionCard(screen, _buildCard(context, step)),
      ],
    );
  }

  Widget _positionCard(Size screen, Widget card) {
    final target = _targetRect;
    if (target == null) return Center(child: card);

    const margin = 16.0;
    final width = math.min(340.0, screen.width - 2 * margin);
    final left = (target.center.dx - width / 2).clamp(
      margin,
      screen.width - margin - width,
    );
    final sized = SizedBox(width: width, child: card);
    // Place the card on whichever side of the target has more room.
    if (target.center.dy > screen.height / 2) {
      return Positioned(
        left: left,
        bottom: screen.height - target.top + 12,
        child: sized,
      );
    }
    return Positioned(left: left, top: target.bottom + 12, child: sized);
  }

  Widget _buildCard(BuildContext context, HelpTourStep step) {
    final theme = Theme.of(context);
    final isLast = _index == widget.steps.length - 1;
    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_index + 1} of ${widget.steps.length}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(step.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(step.body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                if (!isLast)
                  TextButton(
                    onPressed: widget.onFinished,
                    child: const Text('Skip'),
                  ),
                const Spacer(),
                if (_index > 0)
                  TextButton(
                    onPressed: () => _goTo(_index - 1),
                    child: const Text('Back'),
                  ),
                FilledButton(
                  onPressed: () => _goTo(_index + 1),
                  child: Text(isLast ? 'Done' : 'Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dims the whole screen except a rounded cutout over [target].
class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.target, required this.color});

  final Rect? target;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()..addRect(Offset.zero & size);
    final paint = Paint()..color = color;
    final t = target;
    if (t == null) {
      canvas.drawPath(scrim, paint);
      return;
    }
    final hole = Path()
      ..addRRect(
        RRect.fromRectAndRadius(t.inflate(6), const Radius.circular(14)),
      );
    canvas.drawPath(Path.combine(PathOperation.difference, scrim, hole), paint);
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.target != target || oldDelegate.color != color;
}
