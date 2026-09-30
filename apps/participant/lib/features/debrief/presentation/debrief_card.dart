import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../application/debrief_controller.dart';
import '../domain/debrief_repository.dart';
import 'debrief_questions.dart';

/// "A few questions about this session": an optional card on the summary.
/// It shows nothing until the server says there are questions to answer, and
/// never blocks leaving the page. Give it a key per session.
class DebriefCard extends StatefulWidget {
  const DebriefCard({
    super.key,
    required this.repository,
    required this.sessionId,
  });

  final DebriefRepository repository;
  final String sessionId;

  @override
  State<DebriefCard> createState() => _DebriefCardState();
}

class _DebriefCardState extends State<DebriefCard> {
  late final DebriefController _controller;

  @override
  void initState() {
    super.initState();
    _controller = DebriefController(
      repository: widget.repository,
      sessionId: widget.sessionId,
    )..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        return switch (c.phase) {
          DebriefPhase.loading ||
          DebriefPhase.hidden => const SizedBox.shrink(),
          DebriefPhase.thanked => MessageBanner(
            key: const Key('debrief-thanks'),
            kind: BannerKind.success,
            message: c.skipped
                ? 'Skipped. Thank you.'
                : 'Thank you. Your answers help us improve the sessions.',
          ),
          DebriefPhase.asking => _Form(controller: c),
        };
      },
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({required this.controller});

  final DebriefController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final form = c.form!;
    final hasRequired = form.questions.any((q) => q.required);
    return Card(
      key: const Key('debrief-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FocusTraversalGroup(
          // Tab moves through the questions top to bottom, in their order.
          policy: ReadingOrderTraversalPolicy(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'A few questions about this session',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                hasRequired
                    ? 'These questions are optional. If you answer, the ones '
                          'marked Required need an answer.'
                    : 'These questions are optional.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              for (final q in form.questions) ...[
                const SizedBox(height: 16),
                DebriefQuestionRow(
                  key: ValueKey('debrief-${form.version}-${q.key}'),
                  question: q,
                  value: c.answerFor(q.key),
                  enabled: !c.busy,
                  onChanged: (v) => c.setAnswer(q.key, v),
                ),
              ],
              if (c.error != null) ...[
                const SizedBox(height: 16),
                MessageBanner(
                  key: const Key('debrief-error'),
                  message: c.error!,
                  onDismiss: c.dismissError,
                ),
                if (c.needsReload) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const Key('debrief-reload'),
                      onPressed: c.busy ? null : c.reload,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Reload the questions'),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton(
                    key: const Key('debrief-send'),
                    onPressed: c.canSubmit ? c.submit : null,
                    child: const Text('Send answers'),
                  ),
                  TextButton(
                    key: const Key('debrief-skip'),
                    onPressed: c.canSkip ? c.skip : null,
                    child: const Text('Skip these questions'),
                  ),
                  if (c.busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
