import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../ai/presentation/ai_widgets.dart';
import '../application/live_avatar_controller.dart';
import '../domain/live_models.dart';

/// "Live avatar": which providers answer, speak and show the avatar, what a
/// turn and a minute are estimated to cost, the shared budget and how many
/// conversations are open. Everybody who can read the study sees it.
class LiveAvatarCard extends StatelessWidget {
  const LiveAvatarCard({super.key, required this.controller});

  final LiveAvatarController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final s = c.status;
        if (c.unavailable) return const SizedBox.shrink();
        return Card(
          key: const Key('live-avatar-card'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Live avatar', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                const MutedText(
                  'Providers behind the live conversation path. Replies are '
                  "paid from the study's AI budget above.",
                ),
                const SizedBox(height: 12),
                if (c.error != null) ...[
                  MessageBanner(
                    key: const Key('live-status-error'),
                    message: c.error!,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      key: const Key('live-status-retry'),
                      onPressed: c.loading ? null : c.load,
                      child: const Text('Try again'),
                    ),
                  ),
                ] else if (s == null)
                  const Text(
                    'Loading the live avatar status...',
                    key: Key('live-status-loading'),
                  )
                else
                  ..._body(context, s),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _body(BuildContext context, LiveAvatarStatus s) => [
        _ProviderRow(
          keyPrefix: 'live-reply',
          label: 'Reply provider',
          provider: s.reply,
          detail: [
            if (s.reply.effort != null) 'effort ${s.reply.effort}',
          ],
        ),
        const Divider(height: 20),
        _ProviderRow(
          keyPrefix: 'live-speech',
          label: 'Speech provider',
          provider: s.speech,
          detail: [
            if (s.speech.baseUrl != null) s.speech.baseUrl!,
          ],
        ),
        const Divider(height: 20),
        _ProviderRow(
          keyPrefix: 'live-avatar',
          label: 'Avatar provider',
          provider: s.avatar,
          trailing: s.avatar.streaming == false
              ? const KeyedSubtree(
                  key: Key('live-avatar-streaming'),
                  child: StateChip(
                    label: 'No streaming avatar connected',
                    foreground: AppColors.textMuted,
                    outlined: true,
                  ),
                )
              : s.avatar.streaming == true
                  ? const KeyedSubtree(
                      key: Key('live-avatar-streaming'),
                      child: StateChip(
                        label: 'Streaming avatar',
                        foreground: AppColors.success,
                        background: AppColors.successTint,
                      ),
                    )
                  : null,
        ),
        const Divider(height: 20),
        LabelRow(
          label: 'Estimates',
          children: [
            FigureText(
              keyName: 'live-per-turn',
              label: 'Per reply',
              value: '${formatUnits(s.perTurnUnits)} units',
            ),
            FigureText(
              keyName: 'live-per-minute',
              label: 'Avatar per minute',
              value: '${formatUnits(s.avatarPerMinuteUnits)} units',
            ),
          ],
        ),
        const Divider(height: 20),
        LabelRow(
          label: 'Shared budget',
          children: [
            FigureText(
              keyName: 'live-budget-cap',
              label: 'Cap',
              value: formatUnits(s.budget.costCapUnits),
            ),
            FigureText(
              keyName: 'live-budget-spent',
              label: 'Spent',
              value: formatUnits(s.budget.spentUnits),
            ),
            FigureText(
              keyName: 'live-budget-remaining',
              label: 'Remaining',
              value: formatUnits(s.budget.remainingUnits),
            ),
          ],
        ),
        const Divider(height: 20),
        LabelRow(
          label: 'Open now',
          children: [
            FigureText(
              keyName: 'live-open-conversations',
              label: 'Open conversations',
              value: '${s.openConversations}',
            ),
          ],
        ),
        if (s.note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            s.note,
            key: const Key('live-status-note'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ];
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.keyPrefix,
    required this.label,
    required this.provider,
    this.detail = const [],
    this.trailing,
  });

  final String keyPrefix;
  final String label;
  final LiveProviderInfo provider;

  /// Extra words after the name and model (effort, a local address).
  final List<String> detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final name = provider.name.isEmpty ? 'unknown' : provider.name;
    final words = [name, ?provider.model, ...detail];
    return KeyedSubtree(
      key: Key(keyPrefix),
      child: LabelRow(
        label: label,
        children: [
          Text(
            words.join(', '),
            key: Key('$keyPrefix-name'),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: kMonospaceFallback,
            ),
          ),
          KeyedSubtree(
            key: Key('$keyPrefix-state'),
            child: ConfiguredChip(configured: provider.configured),
          ),
          if (provider.synthetic)
            KeyedSubtree(
              key: Key('$keyPrefix-synthetic'),
              child: const SyntheticBadge(),
            ),
          ?trailing,
        ],
      ),
    );
  }
}
