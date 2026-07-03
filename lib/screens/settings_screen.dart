import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
          const _SettingsSection(
            title: 'Support',
            items: [
              _SettingsItem(
                icon: Icons.feedback_outlined,
                title: 'Feedback',
                subtitle: 'Tell us what is working and what needs improvement.',
              ),
              _SettingsItem(
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
              ),
              _SettingsItem(
                icon: Icons.description_outlined,
                title: 'Terms of Use',
                subtitle: 'The terms that apply when using Race Mate.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primaryContainer,
            colors.surfaceContainerHighest,
          ],
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
  const _SettingsSection({
    required this.title,
    required this.items,
  });

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
  });

  final IconData icon;
  final String title;
  final String subtitle;
}
