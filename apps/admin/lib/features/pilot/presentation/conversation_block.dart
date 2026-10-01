import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../live/domain/live_models.dart';
import '../../live/presentation/conversation_widgets.dart';
import 'pilot_widgets.dart';

/// The conversation of the monitored session: where it stands, how many turns
/// were used and whether the participant showed distress. Part of the live
/// panel; shown only for a session that has a conversation.
class ConversationMonitorBlock extends StatelessWidget {
  const ConversationMonitorBlock({super.key, required this.monitor});

  final ConversationMonitor monitor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = monitor;
    final last = m.lastTurn;
    return Column(
      key: const Key('live-conversation'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Conversation', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 10,
          children: [
            FactRow(
              key: const Key('live-conv-status'),
              label: 'Status',
              value: m.isOpen ? 'Open' : 'Closed',
            ),
            FactRow(
              key: const Key('live-conv-mode'),
              label: 'Input mode',
              value: conversationInputModeLabel(m.inputMode),
            ),
            FactRow(
              key: const Key('live-conv-turns'),
              label: 'Turns used',
              value: '${m.turnsUsed}',
            ),
            _Distress(count: m.distress),
            FactRow(
              key: const Key('live-conv-redirects'),
              label: 'Redirects to the topic',
              value: '${m.redirects}',
            ),
            if (!m.isOpen || m.endReason != null)
              FactRow(
                key: const Key('live-conv-end'),
                label: 'End reason',
                value: conversationEndReasonLabel(m.endReason),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          key: const Key('live-conv-last'),
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Last turn',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (last == null)
              const Text('No turn yet')
            else ...[
              Text(conversationRoleLabel(last.role)),
              if (last.tMs != null)
                Text(formatClockMs(last.tMs!),
                    style: kMono.copyWith(fontSize: 13)),
              FlagChips(flags: last.flags),
            ],
          ],
        ),
      ],
    );
  }
}

/// The distress count; highlighted as soon as it is above zero.
class _Distress extends StatelessWidget {
  const _Distress({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const FactRow(
        key: Key('live-conv-distress'),
        label: 'Distress',
        value: '0',
      );
    }
    final theme = Theme.of(context);
    return Container(
      key: const Key('live-conv-distress'),
      width: 232,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.errorTint,
        border: Border.all(color: AppColors.error),
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Row(
        children: [
          const Icon(Icons.priority_high, size: 18, color: AppColors.error),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Distress',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: AppColors.error),
                ),
                Text(
                  '$count',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
