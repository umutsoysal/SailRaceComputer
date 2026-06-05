import 'package:flutter/material.dart';
import '../models/course.dart';
import '../utils/geo.dart';

/// Course setup screen — manage the list of buoys for the race.
class CourseScreen extends StatefulWidget {
  final Course course;
  final ValueChanged<Course> onChanged;

  const CourseScreen({
    super.key,
    required this.course,
    required this.onChanged,
  });

  @override
  State<CourseScreen> createState() => _CourseScreenState();
}

class _CourseScreenState extends State<CourseScreen> {
  late Course _course;

  @override
  void initState() {
    super.initState();
    _course = widget.course;
  }

  void _commit() => widget.onChanged(_course);

  Future<void> _addOrEdit({Buoy? existing, int? index}) async {
    final result = await showDialog<Buoy>(
      context: context,
      builder: (_) => _BuoyDialog(buoy: existing),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        _course.buoys.add(result);
      } else {
        _course.buoys[index] = result;
      }
    });
    _commit();
  }

  void _remove(int i) {
    setState(() => _course.buoys.removeAt(i));
    _commit();
  }

  void _rename() async {
    final controller = TextEditingController(text: _course.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Course name'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    setState(() => _course.name = name);
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_course.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Rename course',
            onPressed: _rename,
          ),
        ],
      ),
      body: _course.buoys.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Add the race marks in order.\nTap + to add a buoy.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
              ),
            )
          : ReorderableListView.builder(
              itemCount: _course.buoys.length,
              onReorder: (oldI, newI) {
                setState(() {
                  if (newI > oldI) newI -= 1;
                  final b = _course.buoys.removeAt(oldI);
                  _course.buoys.insert(newI, b);
                });
                _commit();
              },
              itemBuilder: (ctx, i) {
                final b = _course.buoys[i];
                return ListTile(
                  key: ValueKey('${b.name}-$i'),
                  leading: CircleAvatar(child: Text('${i + 1}')),
                  title: Text(b.name),
                  subtitle: Text(
                    '${b.position.lat.toStringAsFixed(5)}, '
                    '${b.position.lng.toStringAsFixed(5)}  •  '
                    'r=${b.roundingRadiusM.toStringAsFixed(0)} m',
                  ),
                  onTap: () => _addOrEdit(existing: b, index: i),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _remove(i),
                      ),
                      const Icon(Icons.drag_handle),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Add buoy'),
      ),
    );
  }
}

class _BuoyDialog extends StatefulWidget {
  final Buoy? buoy;
  const _BuoyDialog({this.buoy});

  @override
  State<_BuoyDialog> createState() => _BuoyDialogState();
}

class _BuoyDialogState extends State<_BuoyDialog> {
  late final TextEditingController _name;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  late final TextEditingController _radius;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.buoy?.name ?? '');
    _lat = TextEditingController(
        text: widget.buoy?.position.lat.toStringAsFixed(6) ?? '');
    _lng = TextEditingController(
        text: widget.buoy?.position.lng.toStringAsFixed(6) ?? '');
    _radius = TextEditingController(
        text: (widget.buoy?.roundingRadiusM ?? 25.0).toStringAsFixed(0));
  }

  @override
  void dispose() {
    _name.dispose();
    _lat.dispose();
    _lng.dispose();
    _radius.dispose();
    super.dispose();
  }

  String? _validateLat(String? s) {
    final v = double.tryParse(s ?? '');
    if (v == null || v < -90 || v > 90) return 'Latitude must be -90..90';
    return null;
  }

  String? _validateLng(String? s) {
    final v = double.tryParse(s ?? '');
    if (v == null || v < -180 || v > 180) return 'Longitude must be -180..180';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.buoy == null ? 'Add buoy' : 'Edit buoy'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (s) =>
                    (s == null || s.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _lat,
                decoration: const InputDecoration(labelText: 'Latitude'),
                keyboardType: const TextInputType.numberWithOptions(
                    signed: true, decimal: true),
                validator: _validateLat,
              ),
              TextFormField(
                controller: _lng,
                decoration: const InputDecoration(labelText: 'Longitude'),
                keyboardType: const TextInputType.numberWithOptions(
                    signed: true, decimal: true),
                validator: _validateLng,
              ),
              TextFormField(
                controller: _radius,
                decoration: const InputDecoration(
                    labelText: 'Rounding radius (m)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (s) {
                  final v = double.tryParse(s ?? '');
                  if (v == null || v <= 0) return 'Must be > 0';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              Buoy(
                name: _name.text.trim(),
                position: LatLng(
                  double.parse(_lat.text),
                  double.parse(_lng.text),
                ),
                roundingRadiusM: double.parse(_radius.text),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
