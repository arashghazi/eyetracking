import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../application/settings_history_controller.dart';
import 'pilot_widgets.dart';

/// The settings versions of a study, newest first: version, date, author,
/// the rationale and the values each version changed against the one before.
/// Used by the Thresholds section and the Measurement settings tab.
class SettingsHistoryCard extends StatelessWidget {
  const SettingsHistoryCard({super.key, required this.controller});

  final SettingsHistoryController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        return PilotCard(
          title: 'Settings history',
          caption: 'Every real change of the measurement settings is a new '
              'version with who saved it and why. Sessions record the version '
              'they were validated with.',
          trailing: OutlinedButton.icon(
            key: const Key('history-refresh'),
            onPressed: c.loading ? null : c.load,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh'),
          ),
          children: [
            if (c.error != null)
              MessageBanner(key: const Key('history-error'), message: c.error!)
            else if (c.loading && !c.loadedOnce)
              const BusyBox()
            else if (c.items.isEmpty)
              const EmptyNote('No settings versions to show.')
            else
              Column(
                key: const Key('history-list'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < c.items.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _VersionEntry(
                      version: c.items[i],
                      changes: c.changesOf(i),
                      latest: i == 0,
                    ),
                  ],
                ],
              ),
          ],
        );
      },
    );
  }
}

class _VersionEntry extends StatelessWidget {
  const _VersionEntry({
    required this.version,
    required this.changes,
    required this.latest,
  });

  final SettingsVersion version;
  final List<SettingChange> changes;
  final bool latest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Container(
      key: Key('history-${version.version}'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: latest ? AppColors.tealTint : null,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Version ${version.version}', style: theme.textTheme.titleSmall),
              if (latest) Text('current', style: muted),
              Text(
                version.createdAt == null
                    ? 'No date (defaults)'
                    : formatTimestamp(version.createdAt),
                style: muted,
              ),
              Text(
                version.changedBy == null
                    ? 'Author: -'
                    : 'Author: user #${version.changedBy}',
                style: muted,
              ),
            ],
          ),
          if (version.rationale.isNotEmpty) ...[
            const SizedBox(height: 4),
            SelectableText(version.rationale),
          ],
          const SizedBox(height: 6),
          if (changes.isEmpty)
            Text(
              'No earlier version to compare with.',
              style: muted,
            )
          else
            for (final ch in changes)
              Text(
                '${ch.label}: ${ch.text}',
                key: Key('history-${version.version}-${ch.key}'),
                style: theme.textTheme.bodyMedium,
              ),
        ],
      ),
    );
  }
}
