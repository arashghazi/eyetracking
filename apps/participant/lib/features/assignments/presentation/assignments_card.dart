import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../application/assignments_controller.dart';

/// "Your next session": the assignments in order, each with what to do next.
class AssignmentsCard extends StatelessWidget {
  const AssignmentsCard({
    super.key,
    required this.controller,
    required this.ready,
    required this.onConfirmTopic,
    required this.onPrepare,
  });

  final AssignmentsController controller;

  /// The participant may start sessions (consent and demographics done).
  final bool ready;
  final ValueChanged<Assignment> onConfirmTopic;
  final ValueChanged<Assignment> onPrepare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    final items = c.assignments;
    return Card(
      key: const Key('assignments-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your next session', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (c.loading && !c.loadedOnce)
              const Center(child: CircularProgressIndicator())
            else if (c.error != null && !c.loadedOnce)
              Row(
                children: [
                  Expanded(child: Text(c.error!)),
                  OutlinedButton(
                    key: const Key('assignments-retry'),
                    onPressed: c.load,
                    child: const Text('Try again'),
                  ),
                ],
              )
            else if (items.isEmpty)
              Text(
                'Nothing has been assigned to you yet.',
                key: const Key('no-assignments'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(height: 24),
                _AssignmentRow(
                  assignment: items[i],
                  ready: ready,
                  onConfirmTopic: onConfirmTopic,
                  onPrepare: onPrepare,
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class _AssignmentRow extends StatelessWidget {
  const _AssignmentRow({
    required this.assignment,
    required this.ready,
    required this.onConfirmTopic,
    required this.onPrepare,
  });

  final Assignment assignment;
  final bool ready;
  final ValueChanged<Assignment> onConfirmTopic;
  final ValueChanged<Assignment> onPrepare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = assignment;
    final muted = theme.colorScheme.onSurfaceVariant;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          a.protocol.name.isEmpty ? 'Practice session' : a.protocol.name,
          style: theme.textTheme.titleSmall,
        ),
        if (a.topic != null)
          Text('Topic: ${a.topic}',
              style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
      ],
    );

    final Widget action = switch (a.status) {
      AssignmentStatus.pendingTopic => FilledButton(
          key: Key('confirm-topic-${a.id}'),
          onPressed: () => onConfirmTopic(a),
          child: const Text('Confirm my topic'),
        ),
      AssignmentStatus.contentPending => Text(
          'Content being prepared by your researcher',
          key: Key('content-pending-${a.id}'),
          style: theme.textTheme.bodyMedium?.copyWith(color: muted),
        ),
      AssignmentStatus.ready || AssignmentStatus.inProgress => FilledButton(
          key: Key('prepare-${a.id}'),
          onPressed: ready ? () => onPrepare(a) : null,
          child: const Text('Prepare for session'),
        ),
      AssignmentStatus.completed => Row(
          key: Key('done-${a.id}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 22),
            const SizedBox(width: 6),
            Text('Done', style: theme.textTheme.bodyMedium),
          ],
        ),
      _ => Text(assignmentStatusLabel(a.status)),
    };

    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 480;
      if (narrow) {
        return Column(
          key: Key('assignment-${a.id}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [title, const SizedBox(height: 8), action],
        );
      }
      return Row(
        key: Key('assignment-${a.id}'),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: title),
          const SizedBox(width: 12),
          Flexible(child: Align(alignment: Alignment.centerRight, child: action)),
        ],
      );
    });
  }
}
