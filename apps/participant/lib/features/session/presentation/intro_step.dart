import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../application/session_flow_controller.dart';
import '../domain/session_step.dart';
import 'step_list.dart';

/// What will happen, then the button that opens the camera and the session.
class IntroStep extends StatelessWidget {
  const IntroStep({super.key, required this.controller, required this.onHome});

  final SessionFlowController controller;
  final VoidCallback onHome;

  static const stopSentence =
      'You can pause or end at any time and come back later.';

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final blocked = c.blockedReasons;
    final muted = theme.colorScheme.onSurfaceVariant;

    return PageFrame(
      banner: c.error != null
          ? MessageBanner(message: c.error!, onDismiss: c.dismissError)
          : null,
      children: [
        Text(c.hasProtocol ? 'Prepare for session' : 'Start a session',
            style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        StepList(current: SessionStep.intro, protocol: c.hasProtocol),
        const SizedBox(height: 16),
        if (blocked != null)
          _Blocked(reasons: blocked, onHome: onHome)
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What will happen', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const _Bullet(
                    'Camera check',
                    'We make sure the camera can see your face.',
                  ),
                  const _Bullet(
                    'Calibration',
                    'You look at a few dots on the screen, one at a time.',
                  ),
                  const _Bullet(
                    'Validation',
                    'You look at some dots on a picture of a face.',
                  ),
                  _Bullet(
                    'Baseline',
                    c.hasProtocol
                        ? 'You look at a face for a short time. There is nothing to do.'
                        : 'You look at a face for 30 seconds. There is nothing to do.',
                  ),
                  if (c.hasProtocol) ...[
                    _Bullet(
                      'Practice',
                      c.assignment!.isLive
                          ? 'You have a short chat with a virtual avatar, typing or speaking.'
                          : c.assignment!.isInterest
                          ? 'You watch a short video conversation and answer a few questions.'
                          : 'You see a face with a number near it and tell us the number. '
                              'It is not a test.',
                    ),
                    const _Bullet(
                      'Post observation',
                      'You look at the picture or video once more. Nothing is asked.',
                    ),
                    const _Bullet(
                      'Comfort and summary',
                      'We ask how you feel, then you see how the session went.',
                    ),
                  ] else
                    const _Bullet(
                      'Summary',
                      'You see how much of the session could be used.',
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Camera pictures are not stored. Only numbers about where '
                    'your face and eyes point are kept, under your research code.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.tealTint,
              borderRadius: BorderRadius.circular(kRadius),
              border: Border.all(color: AppColors.teal.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 20, color: AppColors.tealDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stopSentence,
                    key: const Key('stop-sentence'),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.tealDark),
                  ),
                ),
              ],
            ),
          ),
          if (c.gazeInfo?.synthetic == true) ...[
            const SizedBox(height: 12),
            const MessageBanner(
              key: Key('intro-synthetic'),
              kind: BannerKind.info,
              message: 'This session uses a development estimator. '
                  'The results are for testing only.',
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                key: const Key('intro-begin'),
                onPressed: c.introReady && !c.busy ? c.begin : null,
                child: Text(c.busy && c.introReady
                    ? 'Starting...'
                    : 'Start camera check'),
              ),
              if (!c.introReady && !c.busy)
                OutlinedButton(
                  key: const Key('intro-retry'),
                  onPressed: c.loadIntro,
                  child: const Text('Try again'),
                ),
              TextButton(
                key: const Key('intro-not-now'),
                onPressed: onHome,
                child: const Text('Not now'),
              ),
            ],
          ),
          if (c.busy && !c.introReady)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.title, this.text);

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.chevron_right, size: 18, color: AppColors.teal),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: '$title. ',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: text, style: theme.textTheme.bodyMedium),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// The server refused to create a session: show why and offer the way home.
class _Blocked extends StatelessWidget {
  const _Blocked({required this.reasons, required this.onHome});

  final List<String> reasons;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('session-blocked'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You cannot start a session yet',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('These steps are still open:'),
            const SizedBox(height: 4),
            for (final r in reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('•  $r', key: const Key('blocked-reason')),
              ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('blocked-home'),
              onPressed: onHome,
              child: const Text('Back to home'),
            ),
          ],
        ),
      ),
    );
  }
}
