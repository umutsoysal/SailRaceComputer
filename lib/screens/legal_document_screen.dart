import 'package:flutter/material.dart';

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.effectiveDate,
    required this.intro,
    required this.sections,
  });

  final String title;
  final String effectiveDate;
  final String intro;
  final List<LegalDocumentSection> sections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            effectiveDate,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(intro, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 24),
          for (final section in sections) ...[
            Text(
              section.heading,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            for (final paragraph in section.paragraphs) ...[
              Text(paragraph, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class LegalDocumentSection {
  const LegalDocumentSection({
    required this.heading,
    required this.paragraphs,
  });

  final String heading;
  final List<String> paragraphs;
}
