import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

/// "How are you feeling right now?" with the protocol's own scale: one large
/// button per label, so it is easy to hit on a phone.
class ComfortQuestion extends StatelessWidget {
  const ComfortQuestion({
    super.key,
    required this.config,
    required this.onAnswer,
    this.onSkip,
    this.busy = false,
    this.title = 'How are you feeling right now?',
  });

  final ComfortConfig config;
  final ValueChanged<int> onAnswer;

  /// Offered as a quiet "I would rather not say".
  final VoidCallback? onSkip;
  final bool busy;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('comfort-question'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'There is no right answer. Choose what fits best.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (var v = 1; v <= config.scaleMax; v++) ...[
              if (v > 1) const SizedBox(height: 8),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  key: Key('comfort-$v'),
                  onPressed: busy ? null : () => onAnswer(v),
                  style: OutlinedButton.styleFrom(
                    textStyle:
                        const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  child: Text(config.labelFor(v), textAlign: TextAlign.center),
                ),
              ),
            ],
            if (onSkip != null) ...[
              const SizedBox(height: 8),
              TextButton(
                key: const Key('comfort-skip'),
                onPressed: busy ? null : onSkip,
                child: const Text('I would rather not say'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
