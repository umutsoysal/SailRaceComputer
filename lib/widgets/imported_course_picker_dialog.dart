import 'package:flutter/material.dart';

import '../services/course_file.dart';

Future<ImportedCourseDefinition?> pickImportedCourse(
  BuildContext context,
  ImportedCourseBundle bundle, {
  String? sourceName,
}) async {
  if (bundle.courses.isEmpty) {
    throw const CourseFileException('File does not contain any courses.');
  }
  if (bundle.courses.length == 1) {
    return bundle.courses.single;
  }

  final from = sourceName == null ? '' : ' from $sourceName';
  return showDialog<ImportedCourseDefinition>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Choose course'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${bundle.name}" contains ${bundle.courses.length} courses$from.\nPick one to load into the app.',
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: bundle.courses.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final imported = bundle.courses[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(imported.name),
                    subtitle: imported.summary == null
                        ? null
                        : Text(imported.summary!),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(ctx, imported),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}
