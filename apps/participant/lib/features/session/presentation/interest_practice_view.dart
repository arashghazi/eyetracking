import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../application/interest_practice_controller.dart';
import '../application/session_flow_controller.dart';
import '../domain/stimulus_geometry.dart';

/// The interest conversation: the video fills the window below the control
/// bar; at the end of a segment the question appears with one large button
/// per option; then the comprehension questions.
class InterestPracticeView extends StatelessWidget {
  const InterestPracticeView({
    super.key,
    required this.flow,
    required this.controller,
  });

  final SessionFlowController flow;
  final InterestPracticeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final i = controller;
        final url = i.videoUrl;
        return ColoredBox(
          key: const Key('interest-stage'),
          color: url != null ? Colors.black : const Color(0xFFF0F2F2),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url != null)
                Padding(
                  padding: const EdgeInsets.only(top: kControlBarHeight),
                  child: AppScope.read(context).videoStage(
                    context,
                    VideoStageConfig(
                      url: url,
                      onEnded: i.onVideoEnded,
                      onError: i.onVideoError,
                      onRect: i.onVideoRect,
                      onPlaying: i.onVideoPlaying,
                    ),
                  ),
                ),
              if (i.caption != null)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: Center(
                    child: Container(
                      key: const Key('video-caption'),
                      constraints: const BoxConstraints(maxWidth: 720),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      color: Colors.black.withValues(alpha: 0.72),
                      child: Text(
                        i.caption!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 17, height: 1.35),
                      ),
                    ),
                  ),
                ),
              if (i.videoProblem != null)
                Padding(
                  padding: const EdgeInsets.only(top: kControlBarHeight),
                  child: _Centered(child: _VideoProblem(controller: i)),
                ),
              if (url == null &&
                  i.videoProblem == null &&
                  i.phase != InterestPhase.playing)
                Padding(
                  padding: const EdgeInsets.only(top: kControlBarHeight),
                  child: _Centered(child: _Questions(controller: i)),
                ),
              if (flow.error != null || i.error != null)
                Positioned(
                  left: 16,
                  right: 16,
                  top: kControlBarHeight + 8,
                  child: MessageBanner(message: flow.error ?? i.error!),
                ),
              if (flow.faceLost)
                Positioned.fill(
                  child: Center(
                    child: Container(
                      key: const Key('face-lost-overlay'),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(kRadius),
                        border: Border.all(color: AppColors.warning),
                      ),
                      child: const Text(
                        "We can't see your face",
                        style:
                            TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: child,
          ),
        ),
      );
}

class _VideoProblem extends StatelessWidget {
  const _VideoProblem({required this.controller});

  final InterestPracticeController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('video-problem'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.videocam_off_outlined, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(controller.videoProblem!,
                      style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'The video could not be loaded. Check your connection and try again.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('video-retry'),
              onPressed: controller.reloading ? null : controller.retryVideo,
              child: Text(controller.reloading ? 'Trying...' : 'Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Questions extends StatelessWidget {
  const _Questions({required this.controller});

  final InterestPracticeController controller;

  @override
  Widget build(BuildContext context) {
    final i = controller;
    final theme = Theme.of(context);
    final q = i.question;
    if (q == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('One moment...', key: Key('working-text')),
            ],
          ),
        ),
      );
    }
    final comprehension = i.phase == InterestPhase.comprehension;
    return Card(
      key: Key(comprehension ? 'comprehension-question' : 'interaction-question'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (comprehension)
              Text(
                'Question ${i.comprehensionIndex + 1} of ${i.comprehensionCount}',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            Text(q.prompt,
                key: const Key('question-prompt'),
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            for (var n = 0; n < q.options.length; n++) ...[
              if (n > 0) const SizedBox(height: 8),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  key: Key('option-$n'),
                  onPressed: i.busy
                      ? null
                      : () => comprehension
                          ? i.answerComprehension(q.options[n])
                          : i.answerInteraction(q.options[n]),
                  style: OutlinedButton.styleFrom(
                    textStyle:
                        const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  child: Text(q.options[n], textAlign: TextAlign.center),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
