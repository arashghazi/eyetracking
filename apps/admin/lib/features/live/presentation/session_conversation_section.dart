import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../ai/presentation/ai_widgets.dart' show MutedText;
import '../application/session_conversation_controller.dart';
import '../domain/live_models.dart';
import 'conversation_widgets.dart';

/// The "Conversation" section of the session detail: what the live avatar
/// talked about, how it ended, the outcome counts and every turn. Shown only
/// for a session that has a conversation.
class SessionConversationSection extends StatefulWidget {
  const SessionConversationSection({
    super.key,
    required this.studyId,
    required this.sessionId,
  });

  final int studyId;
  final String sessionId;

  @override
  State<SessionConversationSection> createState() =>
      _SessionConversationSectionState();
}

class _SessionConversationSectionState
    extends State<SessionConversationSection> {
  late final SessionConversationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SessionConversationController(
      AppScope.read(context).live,
      widget.studyId,
      widget.sessionId,
    )..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final c = _controller;
          final conversation = c.conversation;
          if (c.error != null) {
            return _Frame(
              children: [
                MessageBanner(
                  key: const Key('conversation-error'),
                  message: c.error!,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    key: const Key('conversation-retry'),
                    onPressed: c.loading ? null : c.load,
                    child: const Text('Try again'),
                  ),
                ),
              ],
            );
          }
          // Still reading, or this session has no conversation.
          if (conversation == null) return const SizedBox.shrink();
          return _Frame(children: _body(context, conversation));
        },
      );

  List<Widget> _body(BuildContext context, StaffConversation c) {
    final theme = Theme.of(context);
    final conv = c.conversation;
    final o = c.outcome;
    return [
      Wrap(
        spacing: 16,
        runSpacing: 10,
        children: [
          _Fact('conv-topic', 'Topic', conv.topic.isEmpty ? '-' : conv.topic),
          _Fact('conv-mode', 'Input mode',
              conversationInputModeLabel(conv.inputMode)),
          _Fact('conv-transcript', 'Transcript kept',
              c.textKept ? 'Yes' : 'No'),
          _Fact('conv-status', 'Status', conv.isOpen ? 'Open' : 'Closed'),
          _Fact('conv-end', 'End reason',
              conversationEndReasonLabel(conv.endReason)),
          _Fact('conv-turns', 'Turns used', '${conv.turnsUsed}'),
          _Fact('conv-cost', 'Cost', '${formatUnits(c.costUnits)} units'),
        ],
      ),
      const SizedBox(height: 16),
      Text('Outcome', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(
        key: const Key('conversation-outcome'),
        spacing: 16,
        runSpacing: 10,
        children: [
          _Fact('outcome-participant-turns', 'Participant turns',
              '${o.participantTurns}'),
          _Fact('outcome-on-topic', 'On-topic share',
              formatPercent(o.onTopicShare)),
          _Fact('outcome-redirects', 'Redirects', '${o.redirects}'),
          _Fact('outcome-distress', 'Distress', '${o.distress}',
              alert: o.distress > 0),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        o.note ??
            'On-topic judgements come from the reply model; they describe '
                'the conversation, not understanding.',
        key: const Key('conversation-outcome-note'),
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 16),
      Text('Turns', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      if (c.turns.isEmpty)
        const Text('No turns yet.', key: Key('conversation-no-turns'))
      else
        Column(
          key: const Key('conversation-turns'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final t in c.turns) _TurnTile(turn: t)],
        ),
      const SizedBox(height: 12),
      const MutedText(
        'Opening this section is written to the access log '
        '(live_transcript).',
      ),
      if (c.note.isNotEmpty) ...[
        const SizedBox(height: 4),
        MutedText(c.note),
      ],
    ];
  }
}

const TextStyle _mono = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: kMonospaceFallback,
  fontSize: 13,
);

class _Frame extends StatelessWidget {
  const _Frame({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Card(
          key: const Key('section-conversation'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Conversation',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...children,
              ],
            ),
          ),
        ),
      );
}

/// A label with its value, sized to sit in a wrapping row.
class _Fact extends StatelessWidget {
  const _Fact(this.keyName, this.label, this.value, {this.alert = false});

  final String keyName;
  final String label;
  final String value;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 360),
      child: Column(
        key: Key(keyName),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          SelectableText(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: alert ? AppColors.error : null,
              fontWeight: alert ? FontWeight.w700 : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnTile extends StatelessWidget {
  const _TurnTile({required this.turn});

  final LiveTurn turn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = turn;
    return Container(
      key: Key('turn-${t.index}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.isAvatar ? AppColors.tealTint : null,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                conversationRoleLabel(t.role),
                style: theme.textTheme.labelLarge,
              ),
              Text(
                t.tMs == null ? '-' : formatClockMs(t.tMs!),
                style: _mono,
              ),
              FlagChips(flags: t.flags),
            ],
          ),
          const SizedBox(height: 4),
          if (t.text != null)
            SelectableText(t.text!)
          else
            Text(
              'Text not kept',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}
