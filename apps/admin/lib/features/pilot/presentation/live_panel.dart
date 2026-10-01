import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../ai/presentation/ai_widgets.dart' show MutedText;
import '../../live/domain/live_models.dart';
import '../application/live_monitor_controller.dart';
import 'conversation_block.dart';
import 'pilot_widgets.dart';

/// The status of the monitored session: what the participant is doing, how
/// the last seconds of gaze data looked and the latest events. Read again
/// by [LiveMonitorController] every couple of seconds.
class LivePanel extends StatelessWidget {
  const LivePanel({super.key, required this.controller});

  final LiveMonitorController controller;

  static String segmentText(String? segment) {
    if (segment == null || segment.isEmpty) return 'None open';
    return segment[0].toUpperCase() + segment.substring(1);
  }

  static String payloadText(Map<String, dynamic> payload) {
    if (payload.isEmpty) return '';
    final text = payload.entries.map((e) => '${e.key}=${e.value}').join(', ');
    return text.length > 90 ? '${text.substring(0, 89)}...' : text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    final live = c.live;
    final selected = c.selected;
    final code = live?.participantCode.isNotEmpty == true
        ? live!.participantCode
        : selected?.participantCode ?? '';
    return Card(
      key: const Key('live-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Live: ', style: theme.textTheme.titleMedium),
                if (code.isNotEmpty) CodeText(code),
                if (live != null)
                  Text(
                    sessionOutcomeLabel(live.status, live.endReason),
                    key: const Key('live-status'),
                    style: theme.textTheme.labelLarge,
                  ),
                OutlinedButton.icon(
                  key: const Key('live-close'),
                  onPressed: c.close,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Close'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _pollingNote(context, c),
            if (c.liveError != null) ...[
              const SizedBox(height: 8),
              MessageBanner(key: const Key('live-error'), message: c.liveError!),
            ],
            if (live == null && c.liveError == null)
              const BusyBox()
            else if (live != null) ..._body(context, live, c.conversation),
          ],
        ),
      ),
    );
  }

  Widget _pollingNote(BuildContext context, LiveMonitorController c) {
    final text = c.ended
        ? 'This session has ended. Monitoring stopped.'
        : c.polling
            ? 'Updating every '
                '${(c.pollInterval.inMilliseconds / 1000).toStringAsFixed(1)} s '
                'while this panel is open.'
            : 'Monitoring stopped.';
    return Text(
      text,
      key: Key(c.ended ? 'live-ended-note' : 'live-polling-note'),
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }

  List<Widget> _body(
    BuildContext context,
    LiveStatus live,
    ConversationMonitor? conversation,
  ) {
    final theme = Theme.of(context);
    final stage = live.lastStageResult;
    final validation = live.validation;
    final recent = live.recent;
    final barColor = live.synthetic ? AppColors.textMuted : AppColors.teal;
    return [
      if (live.synthetic) ...[
        const SizedBox(height: 12),
        WarningBox(
          key: const Key('live-synthetic-warning'),
          title: 'Synthetic estimator',
          lines: [
            'This session uses ${live.estimator ?? 'a synthetic estimator'}, '
                'not a real gaze model. The region counts below mean nothing '
                'and must not be used for measurement claims.',
          ],
        ),
      ],
      const SizedBox(height: 12),
      Wrap(
        spacing: 16,
        runSpacing: 10,
        children: [
          FactRow(
            key: const Key('live-fact-segment'),
            label: 'Current segment',
            value: LivePanel.segmentText(live.currentSegment),
          ),
          FactRow(
            key: const Key('live-fact-paused'),
            label: 'Paused',
            value: live.paused ? 'Yes' : 'No',
          ),
          FactRow(
            key: const Key('live-fact-pauses'),
            label: 'Pauses so far',
            value: '${live.pauses}',
          ),
          FactRow(
            key: const Key('live-fact-stage'),
            label: 'Stage index',
            value: live.stageIndex == null ? '-' : '${live.stageIndex}',
          ),
          FactRow(
            key: const Key('live-fact-decision'),
            label: 'Last stage decision',
            value: stage == null
                ? 'No stage finished yet'
                : 'Stage ${stage.stageIndex}: ${stage.decision}'
                    '${stage.reason == null ? '' : ' (${stage.reason})'}',
          ),
          FactRow(
            key: const Key('live-fact-comfort'),
            label: 'Comfort at that stage',
            value: stage?.comfortValue == null
                ? '-'
                : '${stage!.comfortValue}'
                    '${stage.correctRatio == null ? '' : ', correct ${formatPercent(stage.correctRatio)}'}',
          ),
          FactRow(
            key: const Key('live-fact-calibration'),
            label: 'Calibration',
            value: live.calibrationValid ? 'Valid' : 'Not valid',
          ),
          FactRow(
            key: const Key('live-fact-validation'),
            label: 'Validation',
            value: validation == null
                ? 'Not run yet'
                : validation.passed
                    ? 'Passed'
                    : 'Not passed'
                        '${validation.reasons.isEmpty ? '' : ' (${validation.reasons.join(', ')})'}',
          ),
          FactRow(
            key: const Key('live-fact-estimator'),
            label: 'Estimator',
            value: live.estimator ?? '-',
          ),
          FactRow(
            key: const Key('live-fact-samples'),
            label: 'Samples stored',
            value: '${live.samplesTotal}'
                '${live.lastSampleTMs == null ? '' : ', last at ${formatClockMs(live.lastSampleTMs!)}'}',
          ),
          FactRow(
            key: const Key('live-fact-since-event'),
            label: 'Since the last event',
            value: live.secondsSinceLastEvent == null
                ? 'No event yet'
                : '${live.secondsSinceLastEvent!.toStringAsFixed(1)} s ago',
          ),
          FactRow(
            key: const Key('live-fact-observations'),
            label: 'Observations',
            value: '${live.observations}',
          ),
        ],
      ),
      if (conversation != null) ...[
        const SizedBox(height: 16),
        ConversationMonitorBlock(monitor: conversation),
      ],
      const SizedBox(height: 16),
      Text(
        'Last ${(live.recentWindowMs / 1000).round()} s of gaze data '
        '(${recent.samples} samples)',
        style: theme.textTheme.titleSmall,
      ),
      const SizedBox(height: 4),
      ShareBar(
        key: const Key('live-valid-share'),
        label: 'Valid samples',
        share: recent.validShare,
        valueText: formatPercent(recent.validShare, fallback: 'no data'),
        color: barColor,
      ),
      for (final region in LiveRecent.regionKeys)
        ShareBar(
          key: Key('live-region-$region'),
          label: regionLabel(region),
          share: recent.samples == 0 ? null : recent.region(region) / recent.samples,
          valueText: '${recent.region(region)}',
          color: barColor,
        ),
      const SizedBox(height: 16),
      Text('Latest events', style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      if (live.recentEvents.isEmpty)
        const EmptyNote('No events yet.')
      else
        Column(
          key: const Key('live-events'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in live.recentEvents.reversed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Wrap(
                  spacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(formatClockMs(e.tMs), style: kMono.copyWith(fontSize: 13)),
                    Text(e.type, style: theme.textTheme.labelLarge),
                    if (payloadText(e.payload).isNotEmpty)
                      Text(
                        payloadText(e.payload),
                        style: kMono.copyWith(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      if (live.note.isNotEmpty) ...[
        const SizedBox(height: 12),
        MutedText(live.note),
      ],
    ];
  }
}
