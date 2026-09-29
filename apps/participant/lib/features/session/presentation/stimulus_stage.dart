import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../application/session_flow_controller.dart';
import '../domain/session_step.dart';
import '../domain/stimulus_geometry.dart';
import 'face_stimulus.dart';

/// Full-screen stimulus for calibration, validation and the baseline. It
/// fills the whole window, so a dot at (x, y) is at CSS pixel (x, y) of the
/// screen, which is what the server is told.
///
/// No gaze marker is ever drawn.
class StimulusStage extends StatefulWidget {
  const StimulusStage({super.key, required this.controller});

  final SessionFlowController controller;

  @override
  State<StimulusStage> createState() => _StimulusStageState();
}

class _StimulusStageState extends State<StimulusStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final step = c.step;
    final showFace = step != SessionStep.calibration && c.layout != null;
    final dot = _currentDot(c);
    final countdown = c.phase == StepPhase.countdown;

    return ColoredBox(
      key: const Key('stimulus-stage'),
      color: const Color(0xFFF0F2F2),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showFace)
            FaceStimulusView(
              face: c.layout!.faceBox,
              level: c.observationFaceLevel,
              realFaceUrl: c.protocol?.gradual?.realFaceMediaUrl,
            ),
          if (dot != null && !countdown)
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => _Dot(
                key: const Key('target-dot'),
                x: dot.x,
                y: dot.y,
                pulse: _pulse.value,
                capturing: c.stage == TargetStage.capturing,
              ),
            ),
          if (countdown) _Countdown(value: c.countdown, step: step),
          if (dot != null && !countdown) _Caption(controller: c),
          if (step == SessionStep.baseline) ..._baselineOverlays(c),
        ],
      ),
    );
  }

  TargetPoint? _currentDot(SessionFlowController c) {
    if (c.phase != StepPhase.capturing && c.phase != StepPhase.countdown) {
      return null;
    }
    if (c.step == SessionStep.calibration) {
      if (c.targetIndex >= c.calibrationPoints.length) return null;
      return c.calibrationPoints[c.targetIndex];
    }
    if (c.step == SessionStep.validation) {
      if (c.targetIndex >= c.validationSpecs.length) return null;
      final s = c.validationSpecs[c.targetIndex];
      return TargetPoint(s.x, s.y);
    }
    return null;
  }

  List<Widget> _baselineOverlays(SessionFlowController c) => [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Semantics(
            label: 'Progress',
            value: '${(c.baselineProgress * 100).round()} percent',
            child: LinearProgressIndicator(
              key: const Key('baseline-progress'),
              minHeight: 4,
              value: c.baselineProgress,
              backgroundColor: Colors.transparent,
              color: AppColors.teal.withValues(alpha: 0.55),
            ),
          ),
        ),
        if (c.faceLost)
          Positioned.fill(
            child: Center(
              child: Semantics(
                liveRegion: true,
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
          ),
        if (c.streamProblem != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: MessageBanner(message: c.streamProblem!),
          ),
      ];
}

class _Dot extends StatelessWidget {
  const _Dot({
    super.key,
    required this.x,
    required this.y,
    required this.pulse,
    required this.capturing,
  });

  final double x;
  final double y;
  final double pulse;
  final bool capturing;

  static const double radius = 12;

  @override
  Widget build(BuildContext context) {
    // The ring grows and fades; while settling it is larger to catch the eye.
    final ring = radius + (capturing ? 8 : 16) * pulse;
    return Positioned(
      left: x - ring,
      top: y - ring,
      width: ring * 2,
      height: ring * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.teal.withValues(alpha: 0.5 * (1 - pulse)),
                width: 3,
              ),
            ),
          ),
          Container(
            width: radius * 2,
            height: radius * 2,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.teal,
            ),
            alignment: Alignment.center,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.value, required this.step});

  final int value;
  final SessionStep step;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: 'Starting in $value',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(kRadius),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Get ready', style: TextStyle(fontSize: 16)),
              Text(
                '$value',
                key: const Key('countdown-number'),
                style: const TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w600,
                  color: AppColors.teal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.controller});

  final SessionFlowController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final total = c.step == SessionStep.calibration
        ? c.calibrationPoints.length
        : c.validationSpecs.length;
    final name = c.step == SessionStep.validation &&
            c.targetIndex < c.validationSpecs.length
        ? ' · ${c.validationSpecs[c.targetIndex].label}'
        : '';
    return Positioned(
      left: 0,
      right: 0,
      bottom: 12,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(kRadius),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            'Look at the dot · ${c.targetIndex + 1} of $total$name',
            key: const Key('target-caption'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    );
  }
}
