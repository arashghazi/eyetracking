import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../application/my_sessions_controller.dart';

/// "Start a session" call to action and the list of earlier sessions.
class StartSessionCard extends StatelessWidget {
  const StartSessionCard({
    super.key,
    required this.enabled,
    required this.onStart,
  });

  final bool enabled;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Start a session', style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              'Camera and calibration check only',
              key: const Key('free-session-label'),
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: AppColors.tealDark),
            ),
            const SizedBox(height: 4),
            Text(
              enabled
                  ? 'A short guided session with the camera. It takes a few minutes.'
                  : 'Finish the steps above first. Then you can start a session.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('start-session'),
              onPressed: enabled ? onStart : null,
              icon: const Icon(Icons.videocam_outlined, size: 18),
              label: const Text('Start a session'),
            ),
          ],
        ),
      ),
    );
  }
}

class MySessionsCard extends StatelessWidget {
  const MySessionsCard({super.key, required this.controller});

  final MySessionsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('My sessions', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (c.loading && !c.loadedOnce)
              const Center(child: CircularProgressIndicator())
            else if (c.error != null && !c.loadedOnce)
              Row(
                children: [
                  Expanded(child: Text(c.error!)),
                  OutlinedButton(
                    key: const Key('sessions-retry'),
                    onPressed: c.load,
                    child: const Text('Try again'),
                  ),
                ],
              )
            else if (c.sessions.isEmpty)
              Text(
                'No sessions yet.',
                key: const Key('no-sessions'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              for (var i = 0; i < c.sessions.length; i++) ...[
                if (i > 0) const Divider(height: 16),
                _SessionRow(summary: c.sessions[i]),
              ],
          ],
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      key: Key('session-row-${summary.id}'),
      children: [
        Expanded(
          child: Text(
            formatTimestamp(summary.createdAt),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        if (summary.synthetic)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'Development',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: summary.isEnded ? AppColors.successTint : AppColors.warningTint,
            borderRadius: BorderRadius.circular(kRadius),
          ),
          child: Text(
            sessionOutcomeLabel(summary.status, summary.endReason),
            style: theme.textTheme.labelMedium,
          ),
        ),
      ],
    );
  }
}
