import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'legal_document_screen.dart';

Future<void> _launchFeedbackEmail(BuildContext context) async {
  final uri = Uri(
    scheme: 'mailto',
    path: 'usailfasttech+feedback@gmail.com',
    queryParameters: {
      'subject': 'Race Mate Feedback',
      'body': 'Hi,\n\nHere is my feedback about Race Mate:\n\n',
    },
  );
  if (!await launchUrl(uri)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open email app. Send feedback to usailfasttech+feedback@gmail.com',
          ),
        ),
      );
    }
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.onStartTour});

  /// Replays the overlay help tour when the "App Tour" tile is tapped.
  /// The tile is hidden when null.
  final VoidCallback? onStartTour;

  static const _effectiveDate = 'Effective July 3, 2026';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _HeroCard(
            title: 'General App Settings',
            message:
                'Privacy, terms, feedback, and future app preferences will live here.',
          ),
          const SizedBox(height: 16),
          const _AppVersionCard(),
          const SizedBox(height: 16),
          const _SettingsSection(
            title: 'General',
            items: [
              _SettingsItem(
                icon: Icons.tune,
                title: 'App Preferences',
                subtitle: 'Units, alerts, and other race-day defaults.',
              ),
              _SettingsItem(
                icon: Icons.notifications_none,
                title: 'Notifications',
                subtitle: 'Control reminders and race-related alerts.',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: 'Support',
            items: [
              _SettingsItem(
                icon: Icons.feedback_outlined,
                title: 'Feedback',
                subtitle: 'Tell us what is working and what needs improvement.',
                action: _launchFeedbackEmail,
              ),
              if (onStartTour != null)
                _SettingsItem(
                  icon: Icons.tour_outlined,
                  title: 'App Tour',
                  subtitle: 'Replay the quick walkthrough of the main tabs.',
                  action: (_) async => onStartTour!(),
                ),
              const _SettingsItem(
                icon: Icons.help_outline,
                title: 'Help',
                subtitle: 'Tips and support resources for using the app.',
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _SettingsSection(
            title: 'Legal',
            items: [
              _SettingsItem(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy',
                subtitle: 'How your data and location information are handled.',
                destination: _privacyPolicyScreen,
              ),
              _SettingsItem(
                icon: Icons.description_outlined,
                title: 'Terms of Use',
                subtitle: 'The terms that apply when using Race Mate.',
                destination: _termsOfUseScreen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _privacyPolicyScreen(BuildContext context) {
    return const LegalDocumentScreen(
      title: 'Privacy Policy',
      effectiveDate: _effectiveDate,
      intro:
          'Race Mate is built to help sailors set courses, track races with GPS, and export race files when they choose. This policy explains what information the app uses, how it is handled, and what control you have over it.',
      sections: [
        LegalDocumentSection(
          heading: 'Information the app uses',
          paragraphs: [
            'Race Mate uses your device location to power live race metrics, map position, countdown and elapsed race timing, and saved race tracks. If you allow background location on your device, the app may continue receiving location updates while a race is active in the background.',
            'The app also stores course details, race session data, and GPX track exports that you create in the app. This can include course names, buoy positions, timestamps, route history, speed, heading, and related race data.',
          ],
        ),
        LegalDocumentSection(
          heading: 'How your information is used',
          paragraphs: [
            'Your information is used to operate the core features of the app: creating courses, tracking races, showing race metrics, saving finished sessions, and preparing course or GPX files for sharing when you request it.',
            'If Firebase Analytics is configured for a build of Race Mate, the app may also send limited usage events such as screen and tab visits, course saves, and race start or finish actions so the product can be improved. Race Mate should avoid sending raw course names, GPX contents, or full track payloads as analytics event parameters.',
            'Race Mate does not use your location or saved race data for advertising. The app also does not require an account to use its core features.',
          ],
        ),
        LegalDocumentSection(
          heading: 'Where data is stored',
          paragraphs: [
            'Race Mate currently stores your saved course and race data locally on your device using on-device app storage.',
            'If analytics is enabled for the app build you are using, limited usage telemetry may also be sent to Firebase and Google Analytics infrastructure as part of the app analytics service.',
            'When you choose to share a course or GPX file, the data is handed off to the sharing destination you select, such as email, messaging, cloud storage, or another app. Those services handle shared data under their own privacy terms.',
          ],
        ),
        LegalDocumentSection(
          heading: 'What the app does not do',
          paragraphs: [
            'Race Mate does not include in-app advertising, does not sell your personal information, and does not run its own cloud account system for syncing user race history at this time.',
            'If future versions add syncing, user accounts, broader telemetry, or additional data collection beyond what is described here, this policy should be updated before those features are used.',
          ],
        ),
        LegalDocumentSection(
          heading: 'Your choices',
          paragraphs: [
            'You can control location access in your device settings. If you deny location permission, the app will not be able to provide live race tracking or map position features.',
            'You can delete saved race and course items from the app library. You can also remove the app from your device to remove locally stored app data, subject to how your operating system manages backups.',
          ],
        ),
        LegalDocumentSection(
          heading: 'Changes and contact',
          paragraphs: [
            'This policy may be updated as Race Mate evolves. When material changes are made, the effective date should be updated and the latest version should be made available in the app.',
            'If you publish Race Mate with a support or contact address, that contact point should be added here so users know where to send privacy questions.',
          ],
        ),
      ],
    );
  }

  static Widget _termsOfUseScreen(BuildContext context) {
    return const LegalDocumentScreen(
      title: 'Terms of Use',
      effectiveDate: _effectiveDate,
      intro:
          'These Terms of Use govern your use of Race Mate. By using the app, you agree to use it responsibly and only in ways that are lawful and appropriate for real-world sailing conditions.',
      sections: [
        LegalDocumentSection(
          heading: 'Use of the app',
          paragraphs: [
            'Race Mate is a sailing race companion tool. It is intended to help with course setup, GPS-based race tracking, timing, and export of race data.',
            'You are responsible for how you use the app on the water. The app is not a substitute for seamanship, navigation judgment, safety procedures, official race instructions, or compliance with local law and racing rules.',
          ],
        ),
        LegalDocumentSection(
          heading: 'Safety and accuracy',
          paragraphs: [
            'Location, speed, heading, and timing features depend on your device hardware, operating system behavior, permissions, signal conditions, and environmental factors. Those readings may be delayed, interrupted, inaccurate, or unavailable.',
            'You should not rely on Race Mate as your only source of navigation, collision avoidance, weather awareness, or emergency decision-making.',
          ],
        ),
        LegalDocumentSection(
          heading: 'Your content and exports',
          paragraphs: [
            'You keep ownership of the course information, race sessions, and export files you create in the app.',
            'You are responsible for the content you share from Race Mate and for making sure you have the right to share it with your crew, club, race committee, or any third-party service.',
          ],
        ),
        LegalDocumentSection(
          heading: 'Acceptable use',
          paragraphs: [
            'You agree not to misuse the app, interfere with its normal operation, or use it in a way that could harm others, violate applicable law, or break race rules or event requirements.',
            'If Race Mate is distributed through an app store, you must also comply with the terms that apply through that store and your device platform.',
          ],
        ),
        LegalDocumentSection(
          heading: 'Availability and updates',
          paragraphs: [
            'Race Mate may change over time. Features may be added, removed, improved, or discontinued without prior notice.',
            'The app may also require updates to remain compatible with your device or operating system.',
          ],
        ),
        LegalDocumentSection(
          heading: 'Disclaimer and limits',
          paragraphs: [
            'Race Mate is provided as-is and as-available, without any promise that it will always be uninterrupted, error-free, or fit for every racing or navigation situation.',
            'To the fullest extent allowed by applicable law, the publisher of Race Mate is not responsible for losses, damages, or incidents arising from use of the app, including race decisions, missed timing, incorrect readings, lost data, or on-water safety outcomes.',
          ],
        ),
        LegalDocumentSection(
          heading: 'Changes and contact',
          paragraphs: [
            'These terms may be updated as the app evolves. When they are updated, the effective date should be revised and the latest version should be made available in the app.',
            'If you publish Race Mate with a business name, support email, or website, that contact information should be added here so users know where to direct legal or product questions.',
          ],
        ),
      ],
    );
  }
}

class _AppVersionCard extends StatelessWidget {
  const _AppVersionCard();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AppVersionInfo>(
      future: _AppVersionInfo.load(),
      builder: (context, snapshot) {
        final version = snapshot.data;
        final subtitle = version == null
            ? 'Could not read bundled version metadata for this build.'
            : 'Version ${version.marketing}';
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.info_outline),
            ),
            title: const Text('App Version'),
            subtitle: Text(subtitle),
          ),
        );
      },
    );
  }
}

class _AppVersionInfo {
  const _AppVersionInfo({required this.marketing});

  final String marketing;

  static Future<_AppVersionInfo> load() async {
    final raw = await rootBundle.loadString('app_version.json');
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'app_version.json must contain a JSON object.',
      );
    }
    final marketing = decoded['marketing'];
    final androidBuild = decoded['android_build'];
    final iosBuild = decoded['ios_build'];
    if (marketing is! String ||
        androidBuild is! int ||
        iosBuild is! int ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(marketing)) {
      throw const FormatException('app_version.json has invalid version data.');
    }
    return _AppVersionInfo(marketing: marketing);
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.primaryContainer, colors.surfaceContainerHighest],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.items});

  final String title;
  final List<_SettingsItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                _SettingsTile(item: items[i]),
                if (i != items.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.item});

  final _SettingsItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(item.icon),
      ),
      title: Text(item.title),
      subtitle: Text(item.subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        final destination = item.destination;
        if (destination != null) {
          Navigator.of(context).push(MaterialPageRoute(builder: destination));
          return;
        }
        final action = item.action;
        if (action != null) {
          unawaited(action(context));
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item.title} is coming soon.')),
        );
      },
    );
  }
}

class _SettingsItem {
  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.destination,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder? destination;
  final Future<void> Function(BuildContext context)? action;
}
