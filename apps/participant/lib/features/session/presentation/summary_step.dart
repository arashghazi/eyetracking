import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../application/session_flow_controller.dart';
import '../domain/session_step.dart';
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
    return PageFrame(
      banner: c.error != null
          ? MessageBanner(message: c.error!, onDismiss: c.dismissError)
          : null,
      children: [
        Text('Session summary', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        const StepList(current: SessionStep.summary),
        const SizedBox(height: 16),
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
