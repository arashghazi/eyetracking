import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../application/live_practice_controller.dart';

/// Before the conversation: how would you like to talk, and (when the
/// protocol offers it) may the research team keep a written record.
class LiveChoiceCard extends StatelessWidget {
  const LiveChoiceCard({super.key, required this.controller, this.topic});

  final LivePracticeController controller;

  /// The confirmed topic, shown so the participant knows what it is about.
  final String? topic;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      key: const Key('live-choice'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('How would you like to talk?',
                style: theme.textTheme.titleLarge),
            if (topic != null && topic!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('You will chat about $topic.',
                  key: const Key('live-choice-topic'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
            ],
            const SizedBox(height: 12),
            _ModeTile(
              tileKey: const Key('live-mode-typed'),
              icon: Icons.keyboard_outlined,
              title: 'Type',
              subtitle: 'Write your messages and press Send.',
              selected: c.mode == LiveInputMode.typed,
              enabled: !c.busy,
              onTap: () => c.chooseMode(LiveInputMode.typed),
            ),
            if (c.offersSpeech) ...[
              const SizedBox(height: 8),
              _ModeTile(
                tileKey: const Key('live-mode-speech'),
                icon: Icons.mic_none,
                title: 'Speak',
                subtitle: 'Talk to the avatar with your microphone.',
                selected: c.mode == LiveInputMode.speech,
                enabled: !c.busy,
                onTap: () => c.chooseMode(LiveInputMode.speech),
              ),
              const SizedBox(height: 8),
              Text(
                'Your voice is turned into text and the recording is not kept.',
                key: const Key('live-speech-note'),
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ],
            if (c.storeTranscriptOffered) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                key: const Key('live-transcript'),
                value: c.allowTranscript,
                onChanged: c.busy ? null : (v) => c.setAllowTranscript(v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Keep a written record of this conversation for the '
                  'research team',
                ),
                subtitle: const Text(
                  'If you leave it unchecked, only counts are kept.',
                ),
              ),
            ],
            if (c.error != null) ...[
              const SizedBox(height: 8),
              MessageBanner(
                key: const Key('live-choice-error'),
                message: c.error!,
                onDismiss: c.dismissError,
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: const Key('live-begin'),
                onPressed: c.busy ? null : c.begin,
                child: Text(c.busy ? 'Starting...' : 'Start the conversation'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.tileKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final Key tileKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? AppColors.teal : AppColors.border;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: title,
      child: Material(
        color: selected ? AppColors.tealTint : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadius),
          side: BorderSide(color: color, width: selected ? 2 : 1),
        ),
        child: InkWell(
          key: tileKey,
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(kRadius),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(icon, color: selected ? AppColors.tealDark : null),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle, color: AppColors.teal),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
