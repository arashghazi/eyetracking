import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

/// The three outcomes of a practice session side by side (stacked on a
/// narrow screen): gaze, comprehension (or the number task, or the live
/// conversation) and comfort, followed by the improvement line.
class OutcomesView extends StatelessWidget {
  const OutcomesView({super.key, required this.outcomes, this.path});

  final SessionOutcomes outcomes;

  /// Decides between the comprehension and the number-task card.
  final ProtocolPath? path;

  /// The live path has no comprehension questions: the conversation card
  /// takes their place. Also shown whenever the server sent a conversation
  /// outcome.
  bool get _showConversation =>
      path == ProtocolPath.liveConversation ||
      (path == null && outcomes.conversation != null);

  bool get _showNumberTask {
    if (path != null) return path == ProtocolPath.gradualFace;
    return outcomes.comprehension.answered == 0 &&
        outcomes.numberTask.trials > 0;
  }

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _GazeCard(gaze: outcomes.gaze),
      if (_showConversation)
        _ConversationCard(conversation: outcomes.conversation)
      else if (_showNumberTask)
        _NumberTaskCard(task: outcomes.numberTask)
      else
        _ComprehensionCard(result: outcomes.comprehension),
      _ComfortCard(comfort: outcomes.comfort),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth >= 640) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: cards[i]),
                  ],
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                cards[i],
              ],
            ],
          );
        }),
        const SizedBox(height: 12),
        _ImprovementLine(
          improvement: outcomes.improvement,
          live: _showConversation,
        ),
      ],
    );
  }
}

class _OutcomeCard extends StatelessWidget {
  const _OutcomeCard({
    required this.keyName,
    required this.title,
    required this.children,
  });

  final String keyName;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key(keyName),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.keyName});

  final String label;
  final String value;
  final String? keyName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              key: keyName == null ? null : Key(keyName!),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.keyName});

  final String text;
  final String? keyName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        key: keyName == null ? null : Key(keyName!),
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _GazeCard extends StatelessWidget {
  const _GazeCard({required this.gaze});

  final GazeOutcome gaze;

  @override
  Widget build(BuildContext context) {
    final ok = gaze.evaluable &&
        gaze.baselineEyeShare != null &&
        gaze.postEyeShare != null;
    return _OutcomeCard(
      keyName: 'outcome-gaze',
      title: 'Gaze',
      children: [
        if (ok) ...[
          _Fact('Eyes at the start', formatPercent(gaze.baselineEyeShare),
              keyName: 'gaze-baseline'),
          _Fact('Eyes at the end', formatPercent(gaze.postEyeShare),
              keyName: 'gaze-post'),
          const _Note('Share of usable time spent on the eye region.'),
        ] else ...[
          const _Fact('Eye region', 'Not evaluable', keyName: 'gaze-status'),
          if (outcomeReasonLabel(gaze.reason).isNotEmpty)
            _Note(outcomeReasonLabel(gaze.reason), keyName: 'gaze-reason'),
        ],
      ],
    );
  }
}

class _ComprehensionCard extends StatelessWidget {
  const _ComprehensionCard({required this.result});

  final ComprehensionOutcome result;

  @override
  Widget build(BuildContext context) {
    return _OutcomeCard(
      keyName: 'outcome-comprehension',
      title: 'Comprehension',
      children: result.answered == 0
          ? const [_Fact('Questions', 'None answered')]
          : [
              _Fact('Answered', '${result.answered}'),
              _Fact(
                'Correct',
                '${result.correct}'
                    '${result.share == null ? '' : ' (${formatPercent(result.share)})'}',
                keyName: 'comprehension-correct',
              ),
            ],
    );
  }
}

/// The live conversation: how many messages, how much of it stayed on the
/// topic (judged by the reply model) and how it ended.
class _ConversationCard extends StatelessWidget {
  const _ConversationCard({required this.conversation});

  final ConversationOutcome? conversation;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final reason = liveEndReasonLabel(c?.endReason);
    return _OutcomeCard(
      keyName: 'outcome-conversation',
      title: 'Conversation',
      children: c == null || c.participantTurns == 0
          ? [
              const _Fact('Your messages', 'None sent',
                  keyName: 'conversation-turns'),
              if (reason.isNotEmpty)
                _Fact('How it ended', reason, keyName: 'conversation-end'),
            ]
          : [
              _Fact('Your messages', '${c.participantTurns}',
                  keyName: 'conversation-turns'),
              _Fact(
                'On topic',
                c.onTopicShare == null
                    ? 'Not judged'
                    : formatPercent(c.onTopicShare),
                keyName: 'conversation-on-topic',
              ),
              if (reason.isNotEmpty)
                _Fact('How it ended', reason, keyName: 'conversation-end'),
              const _Note(
                'On topic is judged by the reply model, so it is a rough '
                'guide to the conversation, not to how well you did.',
                keyName: 'conversation-note',
              ),
            ],
    );
  }
}

class _NumberTaskCard extends StatelessWidget {
  const _NumberTaskCard({required this.task});

  final NumberTaskOutcome task;

  @override
  Widget build(BuildContext context) {
    return _OutcomeCard(
      keyName: 'outcome-number-task',
      title: 'Number task',
      children: task.trials == 0
          ? const [_Fact('Numbers', 'None shown')]
          : [
              _Fact('Numbers shown', '${task.trials}'),
              _Fact(
                'Matched',
                '${task.correct}'
                    '${task.share == null ? '' : ' (${formatPercent(task.share)})'}',
                keyName: 'number-task-correct',
              ),
              _Fact('Stages completed', '${task.stagesCompleted}'),
            ],
    );
  }
}

class _ComfortCard extends StatelessWidget {
  const _ComfortCard({required this.comfort});

  final ComfortOutcome comfort;

  @override
  Widget build(BuildContext context) {
    return _OutcomeCard(
      keyName: 'outcome-comfort',
      title: 'Comfort',
      children: comfort.answers == 0
          ? [
              const _Fact('Answers', 'None given'),
              if (comfort.endedEarly) const _Note('The session ended early.'),
            ]
          : [
              _Fact('Lowest', '${comfort.min ?? '-'}', keyName: 'comfort-min'),
              _Fact(
                'Average',
                comfort.mean == null ? '-' : comfort.mean!.toStringAsFixed(1),
                keyName: 'comfort-mean',
              ),
              _Fact('Low answers', '${comfort.lowCount}', keyName: 'comfort-low'),
              if (comfort.pauses > 0) _Fact('Pauses', '${comfort.pauses}'),
              if (comfort.endedEarly) const _Note('The session ended early.'),
            ],
    );
  }
}

/// "All three criteria met", "Not met" or "Cannot be judged yet" with the
/// reason.
class _ImprovementLine extends StatelessWidget {
  const _ImprovementLine({required this.improvement, this.live = false});

  final ImprovementOutcome improvement;

  /// The third criterion is "the conversation held" on the live path.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = improvement.result;
    final (text, icon, color) = switch (result) {
      true => ('All three criteria met', Icons.check_circle, AppColors.success),
      false => ('Not met', Icons.remove_circle_outline, AppColors.warning),
      null => (
          'Cannot be judged yet',
          Icons.hourglass_empty,
          AppColors.textMuted
        ),
    };
    final reason = outcomeReasonLabel(improvement.reason);
    return Card(
      key: const Key('outcome-improvement'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Did it help?', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    key: const Key('improvement-text'),
                    style: theme.textTheme.titleMedium?.copyWith(color: color),
                  ),
                ),
              ],
            ),
            if (result == null && reason.isNotEmpty)
              _Note(reason, keyName: 'improvement-reason'),
            if (improvement.eligible) ...[
              const SizedBox(height: 8),
              _Criterion('Eye share went up', improvement.eyeShareUp),
              _Criterion('Comfort did not get worse', improvement.comfortNotWorse),
              _Criterion(
                  live ? 'The conversation held' : 'Understanding was kept',
                  improvement.comprehensionMaintained),
            ],
          ],
        ),
      ),
    );
  }
}

class _Criterion extends StatelessWidget {
  const _Criterion(this.label, this.met);

  final String label;
  final bool? met;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (met) {
      true => (Icons.check, AppColors.success),
      false => (Icons.close, AppColors.warning),
      null => (Icons.remove, AppColors.textMuted),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
