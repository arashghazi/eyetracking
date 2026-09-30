import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../debrief/presentation/debrief_card.dart';
import '../application/segment_recorder.dart';
import '../application/session_flow_controller.dart';
import '../domain/session_step.dart';
import 'comfort_question.dart';
import 'step_list.dart';
import 'summary_view.dart';

/// Last step: the summary, or a retry when it could not be loaded.
class SummaryStep extends StatelessWidget {
  const SummaryStep({super.key, required this.controller, required this.onHome});

  final SessionFlowController controller;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final summary = c.summary;
    if (c.askingComfort) return _ComfortStep(controller: c);
    final stopped = c.gradual?.end == PracticeEnd.stopped;
    final debrief = AppScope.maybeRead(context)?.debrief;
    return PageFrame(
      maxWidth: 960,
      // The optional debrief card keeps what was typed while it is scrolled
      // out of view.
      buildAll: true,
      banner: c.error != null
          ? MessageBanner(message: c.error!, onDismiss: c.dismissError)
          : null,
      children: [
        Text('Session summary', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        StepList(current: SessionStep.summary, protocol: c.hasProtocol),
        const SizedBox(height: 16),
        if (stopped) ...[
          const MessageBanner(
            key: Key('practice-stopped-note'),
            kind: BannerKind.info,
            message: 'We stopped the practice here. Stopping when it does not '
                'feel good is part of the plan. Thank you for taking part.',
          ),
          const SizedBox(height: 12),
        ],
        if (summary == null)
          c.busy
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    key: const Key('summary-retry'),
                    onPressed: c.reloadSummary,
                    child: const Text('Try again'),
                  ),
                )
        else
          SummaryView(summary: summary),
        if (summary != null && summary.isEnded && debrief != null) ...[
          const SizedBox(height: 12),
          DebriefCard(
            key: ValueKey('debrief-${summary.id}'),
            repository: debrief,
            sessionId: summary.id,
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const Key('summary-home'),
            onPressed: onHome,
            child: const Text('Back to home'),
          ),
        ),
      ],
    );
  }
}

/// The final comfort question of a protocol session, before the summary.
class _ComfortStep extends StatelessWidget {
  const _ComfortStep({required this.controller});

  final SessionFlowController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    return PageFrame(
      banner: c.error != null
          ? MessageBanner(message: c.error!, onDismiss: c.dismissError)
          : null,
      children: [
        Text('Almost done', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        StepList(current: SessionStep.summary, protocol: c.hasProtocol),
        const SizedBox(height: 16),
        ComfortQuestion(
          config: c.protocol?.comfort ?? const ComfortConfig(),
          title: 'How did the session feel?',
          busy: c.busy,
          onAnswer: c.answerFinalComfort,
          onSkip: c.skipFinalComfort,
        ),
      ],
    );
  }
}
