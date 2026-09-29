import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../application/gradual_practice_controller.dart';
import '../application/session_flow_controller.dart';
import '../domain/number_placement.dart';
import '../domain/practice_trials.dart';
import '../domain/stimulus_geometry.dart';
import 'comfort_question.dart';
import 'face_stimulus.dart';
import 'response_controls.dart';
import 'symbol_glyph.dart';

/// Full-screen stage of the gradual face practice: the face at the stage's
/// level, the number near it, and the answer controls at the bottom. Between
/// stages it shows the comfort question and the server's decision on a plain
/// background. It never shows a score.
///
/// It fills the window, so a number at (x, y) is at CSS pixel (x, y).
class GradualPracticeView extends StatelessWidget {
  const GradualPracticeView({
    super.key,
    required this.flow,
    required this.controller,
  });

  final SessionFlowController flow;
  final GradualPracticeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final g = controller;
        final showFace = g.phase == GradualPhase.leadIn ||
            g.phase == GradualPhase.trial ||
            g.phase == GradualPhase.between;
        return ColoredBox(
          key: const Key('practice-stage'),
          color: const Color(0xFFF0F2F2),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (showFace)
                FaceStimulusView(
                  face: g.layout.faceBox,
                  level: g.stage.faceLevel,
                  realFaceUrl: g.config.realFaceMediaUrl,
                ),
              if (g.phase == GradualPhase.trial && g.stimulus != null)
                _NumberMark(
                  trial: g.stimulus!,
                  fontSize: numberFontSize(g.layout.faceBox),
                ),
              if (showFace) _Caption(controller: g),
              if (g.phase == GradualPhase.trial && g.stimulus != null)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 0,
                  height: practiceBarReserve(flow.screen),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: flow.screen.w - 16,
                        child: ResponseControls(
                          key: ValueKey('trial-${g.stageIndex}-${g.trialNumber}-'
                              '${g.stimulus!.shown}'),
                          input: g.stimulus!.input,
                          options: g.stimulus!.options,
                          touch: flow.profile?.responseMode == ResponseMode.touch,
                          onSubmit: g.submit,
                        ),
                      ),
                    ),
                  ),
                ),
              if (!showFace)
                Padding(
                  padding: const EdgeInsets.only(top: kControlBarHeight),
                  child: _Panel(controller: g),
                ),
              if (flow.error != null)
                Positioned(
                  left: 16,
                  right: 16,
                  top: kControlBarHeight + 8,
                  child: MessageBanner(
                    message: flow.error!,
                    onDismiss: flow.dismissError,
                  ),
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

/// The number or symbol, drawn in its box.
class _NumberMark extends StatelessWidget {
  const _NumberMark({required this.trial, required this.fontSize});

  final TrialStimulus trial;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final r = trial.placement.rect;
    return Positioned(
      left: r.x,
      top: r.y,
      width: r.w,
      height: r.h,
      child: Container(
        key: const Key('trial-number'),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(2),
        ),
        child: trial.input == TrialInput.symbol
            ? SymbolGlyph(name: trial.shown, size: fontSize)
            : Text(
                trial.shown,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                  height: 1,
                ),
              ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.controller});

  final GradualPracticeController controller;

  @override
  Widget build(BuildContext context) {
    final g = controller;
    final text = g.phase == GradualPhase.leadIn
        ? 'Get ready'
        : (g.phase == GradualPhase.trial
            ? '${g.trialNumber} of ${g.trialCount}'
            : null);
    if (text == null) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      top: kControlBarHeight + 6,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(kRadius),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(text,
              key: const Key('practice-caption'),
              style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }
}

/// Comfort question, decision message, waiting and retry.
class _Panel extends StatelessWidget {
  const _Panel({required this.controller});

  final GradualPracticeController controller;

  @override
  Widget build(BuildContext context) {
    final g = controller;
    final theme = Theme.of(context);
    final Widget child = switch (g.phase) {
      GradualPhase.comfort => ComfortQuestion(
          config: g.comfort,
          onAnswer: g.answerComfort,
          onSkip: g.skipComfort,
        ),
      GradualPhase.decision => Card(
          key: const Key('decision-card'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(g.decisionMessage,
                    key: const Key('decision-message'),
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('decision-continue'),
                  onPressed: g.continueAfterDecision,
                  child: Text(g.decisionButton),
                ),
              ],
            ),
          ),
        ),
      GradualPhase.problem => Card(
          key: const Key('practice-problem'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MessageBanner(message: g.error ?? 'Something went wrong.'),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('practice-retry'),
                  onPressed: g.retry,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      _ => const Card(
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
        ),
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: child,
        ),
      ),
    );
  }
}
