import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../application/live_practice_controller.dart';
import '../application/session_flow_controller.dart';
import '../domain/stimulus_geometry.dart';
import 'live_choice_card.dart';
import 'live_inputs.dart';

/// The live conversation: the choice card first, then the avatar's video in
/// a stage box with the caption, the voice switch, the turn counter and the
/// input beside it (below it on a narrow window). The window itself never
/// scrolls, so the video, and the face regions posted for the gaze, stay
/// where they were measured.
class LivePracticeView extends StatelessWidget {
  const LivePracticeView({
    super.key,
    required this.flow,
    required this.controller,
  });

  final SessionFlowController flow;
  final LivePracticeController controller;

  /// Window width from which the panel sits beside the video.
  static const wideFrom = kLiveWideWidth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        return ColoredBox(
          key: const Key('live-practice'),
          color: const Color(0xFFF0F2F2),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: kControlBarHeight),
                child: switch (c.phase) {
                  LivePhase.loading => _Centered(child: _Loading(controller: c)),
                  LivePhase.choose => _Centered(
                      child: LiveChoiceCard(
                        controller: c,
                        topic: flow.assignment?.topic,
                      ),
                    ),
                  LivePhase.conversation ||
                  LivePhase.ended =>
                    _ConversationLayout(flow: flow, controller: c),
                  LivePhase.post => _AvatarStage(flow: flow, controller: c),
                  LivePhase.finished => const SizedBox.shrink(),
                },
              ),
              if (flow.error != null)
                Positioned(
                  left: 16,
                  right: 16,
                  top: kControlBarHeight + 8,
                  child: MessageBanner(
                    key: const Key('live-flow-error'),
                    message: flow.error!,
                    onDismiss: flow.dismissError,
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

class _Loading extends StatelessWidget {
  const _Loading({required this.controller});

  final LivePracticeController controller;

  @override
  Widget build(BuildContext context) {
    final error = controller.loadError;
    return Card(
      key: const Key('live-loading'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: error == null
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Flexible(child: Text('Getting the conversation ready...')),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error, key: const Key('live-load-error')),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('live-load-retry'),
                    onPressed: controller.load,
                    child: const Text('Try again'),
                  ),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------- conversation

class _ConversationLayout extends StatelessWidget {
  const _ConversationLayout({required this.flow, required this.controller});

  final SessionFlowController flow;
  final LivePracticeController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final stage = _AvatarStage(flow: flow, controller: controller);
      if (box.maxWidth >= LivePracticeView.wideFrom) {
        return Row(
          children: [
            Expanded(child: stage),
            Container(
              width: 400,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(left: BorderSide(color: AppColors.border)),
              ),
              child: _Panel(controller: controller, flow: flow, fill: true),
            ),
          ],
        );
      }
      return Column(
        children: [
          Expanded(child: stage),
          Container(
            constraints: BoxConstraints(maxHeight: box.maxHeight * 0.66),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: _Panel(controller: controller, flow: flow, fill: false),
          ),
        ],
      );
    });
  }
}

/// The avatar's video in its box, with the "we can't see your face" note
/// over it when the camera lost the participant.
class _AvatarStage extends StatelessWidget {
  const _AvatarStage({required this.flow, required this.controller});

  final SessionFlowController flow;
  final LivePracticeController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final url = c.videoUrl;
    return Stack(
      key: const Key('live-avatar-stage'),
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (url != null)
          KeyedSubtree(
            key: ValueKey('live-video-${c.videoAttempt}'),
            child: AppScope.read(context).videoStage(
              context,
              VideoStageConfig(
                url: url,
                loop: true,
                muted: true,
                onPlaying: c.onVideoPlaying,
                onRect: c.onVideoRect,
                onError: c.onVideoError,
              ),
            ),
          ),
        if (c.videoProblem != null)
          Center(
            child: Card(
              key: const Key('live-video-problem'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(c.videoProblem!),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      key: const Key('live-video-retry'),
                      onPressed: c.retryVideo,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (c.videoMissing)
          const Center(
            child: Text(
              'The avatar has no picture. You can still talk.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        if (flow.faceLost)
          Positioned.fill(
            child: Center(
              child: Container(
                key: const Key('face-lost-overlay'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(kRadius),
                  border: Border.all(color: AppColors.warning),
                ),
                child: const Text(
                  "We can't see your face",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Everything beside (or under) the video: what the avatar says, the
/// switches and counters, a calm offer of a break, errors, and the input.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.controller,
    required this.flow,
    required this.fill,
  });

  final LivePracticeController controller;
  final SessionFlowController flow;

  /// The panel fills the height it is given (beside the video); otherwise it
  /// is as tall as its content, up to its limit.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final ended = c.phase == LivePhase.ended;
    return Column(
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          fit: fill ? FlexFit.tight : FlexFit.loose,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // What needs an answer comes first, so a narrow window that
                // scrolls its panel still shows it.
                if (c.error != null) ...[
                  _ErrorBox(controller: c),
                  const SizedBox(height: 8),
                ],
                if (c.distress) ...[
                  _DistressBanner(controller: c, flow: flow),
                  const SizedBox(height: 8),
                ],
                if (c.avatar?.synthetic == true) ...[
                  const _DevelopmentBadge(),
                  const SizedBox(height: 8),
                ],
                _Toolbar(controller: c, ended: ended),
                const SizedBox(height: 8),
                _Caption(controller: c),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: ended
              ? _Ended(controller: c)
              : c.typing
                  ? LiveTypedInput(controller: c)
                  : LiveSpeechInput(controller: c),
        ),
        if (!ended)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              c.busy
                  ? 'One moment...'
                  : 'You can pause or end the conversation at any time.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _DevelopmentBadge extends StatelessWidget {
  const _DevelopmentBadge();

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('live-synthetic-badge'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.warningTint,
          borderRadius: BorderRadius.circular(kRadius),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
        ),
        child: const Text(
          "Development avatar - sample face and your browser's voice",
          style: TextStyle(fontSize: 12.5, color: AppColors.warning),
        ),
      );
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller, required this.ended});

  final LivePracticeController controller;
  final bool ended;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final left = c.turnsLeft;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          ended
              ? 'Conversation ended'
              : left == 1
                  ? '1 turn left'
                  : '$left turns left',
          key: const Key('live-turns-left'),
          style: theme.textTheme.labelLarge,
        ),
        if (c.canSpeak)
          OutlinedButton.icon(
            key: const Key('live-voice-toggle'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: c.toggleVoice,
            icon: Icon(c.voiceOn ? Icons.volume_up : Icons.volume_off, size: 18),
            label: Text(c.voiceOn ? 'Voice on' : 'Voice off'),
          ),
        if (!ended)
          OutlinedButton(
            key: const Key('live-end'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: c.busy ? null : c.endConversation,
            child: const Text('End conversation'),
          ),
      ],
    );
  }
}

/// The avatar's current line, and what the server heard from the
/// participant (so a spoken message can be checked).
class _Caption extends StatelessWidget {
  const _Caption({required this.controller});

  final LivePracticeController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final heard = c.heard;
    final text = c.caption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (heard != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'You: $heard',
              key: const Key('live-heard'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        Semantics(
          liveRegion: true,
          container: true,
          child: Container(
            key: const Key('live-caption'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.tealTint,
              borderRadius: BorderRadius.circular(kRadius),
              border: Border.all(color: AppColors.teal.withValues(alpha: 0.3)),
            ),
            child: Text(
              text ?? '...',
              key: const Key('live-caption-text'),
              style: const TextStyle(fontSize: 17, height: 1.35),
            ),
          ),
        ),
      ],
    );
  }
}

class _DistressBanner extends StatelessWidget {
  const _DistressBanner({required this.controller, required this.flow});

  final LivePracticeController controller;
  final SessionFlowController flow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const Key('live-distress'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.successTint,
          borderRadius: BorderRadius.circular(kRadius),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("It's okay to take a break.",
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: AppColors.success)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const Key('live-distress-pause'),
                  onPressed: flow.canPause ? flow.pause : null,
                  child: const Text('Pause'),
                ),
                OutlinedButton(
                  key: const Key('live-distress-continue'),
                  onPressed: controller.dismissDistress,
                  child: const Text('Keep talking'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.controller});

  final LivePracticeController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const Key('live-error'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.errorTint,
          borderRadius: BorderRadius.circular(kRadius),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.error!,
              key: const Key('live-error-text'),
              style: const TextStyle(color: AppColors.error),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('live-error-action'),
              onPressed: c.busy ? null : (c.conflict ? c.reload : c.dismissError),
              child: Text(c.conflict ? 'Reload' : 'Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ended extends StatelessWidget {
  const _Ended({required this.controller});

  final LivePracticeController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reason = liveEndReasonLabel(controller.endReason);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('The conversation has ended.',
            key: const Key('live-ended'), style: theme.textTheme.titleMedium),
        if (reason.isNotEmpty)
          Text(
            reason,
            key: const Key('live-end-reason'),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const Key('live-continue'),
            onPressed: controller.continueAfterEnd,
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }
}
