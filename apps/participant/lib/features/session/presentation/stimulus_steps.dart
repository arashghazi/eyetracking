import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../application/session_flow_controller.dart';
import '../domain/session_step.dart';
import '../domain/stimulus_geometry.dart';
import 'result_panels.dart';
import 'stimulus_stage.dart';

/// Body of calibration, validation and baseline. Instruction and result
/// panels sit below the control bar; the stimulus fills the whole window.
class StimulusStepBody extends StatelessWidget {
  const StimulusStepBody({super.key, required this.controller, required this.onEnd});

  final SessionFlowController controller;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.stimulusVisible && c.phase != StepPhase.paused) {
      return StimulusStage(controller: c);
    }
    return Padding(
      padding: const EdgeInsets.only(top: kControlBarHeight),
      child: PageFrame(
        banner: c.error != null
            ? MessageBanner(message: c.error!, onDismiss: c.dismissError)
            : null,
        children: [_panel(context, c)],
      ),
    );
  }

  Widget _panel(BuildContext context, SessionFlowController c) {
    switch (c.phase) {
      case StepPhase.paused:
        return _PausedPanel(controller: c, onEnd: onEnd);
      case StepPhase.changed:
        return _ChangedPanel(controller: c);
      case StepPhase.posting:
        return _Working(
          text: c.step == SessionStep.calibration
              ? 'Checking your calibration...'
              : 'Checking the validation...',
        );
      default:
        break;
    }
    return switch (c.step) {
      SessionStep.calibration => _calibrationPanel(c),
      SessionStep.validation => _validationPanel(c),
      _ => _baselinePanel(c),
    };
  }

  Widget _calibrationPanel(SessionFlowController c) {
    final result = c.calibration;
    if (c.phase == StepPhase.result && result != null) {
      return CalibrationResultPanel(
        result: result,
        onContinue: c.continueToValidation,
        onRetry: c.startCalibration,
      );
    }
    final n = c.settings?.calibrationPoints ?? 9;
    return _Instructions(
      title: 'Calibration',
      text: 'A dot will appear on the screen. Look at it until it moves. '
          'There are $n dots. Keep your head as still as you can.',
      buttonKey: 'calibration-start',
      buttonLabel: 'Start calibration',
      onStart: c.startCalibration,
    );
  }

  Widget _validationPanel(SessionFlowController c) {
    final result = c.validation;
    if (c.phase == StepPhase.result && result != null) {
      return ValidationResultPanel(
        result: result,
        specs: c.validationSpecs,
        allowContinueWithoutValidation: c.allowContinueWithoutValidation,
        cardTooSmall: c.faceLayout?.fits == false,
        onContinue: c.continueToBaseline,
        onRecalibrate: c.recalibrate,
        onContinueWithout: c.continueToBaseline,
      );
    }
    return _Instructions(
      title: 'Validation',
      text: 'You will see a picture of a face. Look at each dot that appears '
          'on or around it. There are 7 dots.',
      buttonKey: 'validation-start',
      buttonLabel: 'Start validation',
      onStart: c.startValidation,
    );
  }

  Widget _baselinePanel(SessionFlowController c) => _Instructions(
        title: 'Baseline',
        text: 'Next you will see a face for '
            '${c.timing.baseline.inSeconds} seconds. Just look at it '
            'naturally. There is nothing to do and nothing will be asked.',
        buttonKey: 'baseline-start',
        buttonLabel: 'Start',
        onStart: c.startBaseline,
        busy: c.busy,
      );
}

class _Instructions extends StatelessWidget {
  const _Instructions({
    required this.title,
    required this.text,
    required this.buttonKey,
    required this.buttonLabel,
    required this.onStart,
    this.busy = false,
  });

  final String title;
  final String text;
  final String buttonKey;
  final String buttonLabel;
  final VoidCallback onStart;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(text, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 16),
            FilledButton(
              key: Key(buttonKey),
              onPressed: busy ? null : onStart,
              child: Text(busy ? 'Starting...' : buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _Working extends StatelessWidget {
  const _Working({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(text, key: const Key('working-text'))),
            ],
          ),
        ),
      );
}

class _PausedPanel extends StatelessWidget {
  const _PausedPanel({required this.controller, required this.onEnd});

  final SessionFlowController controller;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('paused-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pause_circle_outline, color: AppColors.teal),
                const SizedBox(width: 8),
                Text('Paused', style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'The camera is off and nothing is being recorded. Continue when '
              'you are ready, or end the session and come back later.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const Key('resume-panel'),
                  onPressed: controller.canResume ? controller.resume : null,
                  child: const Text('Resume'),
                ),
                OutlinedButton(
                  key: const Key('end-panel'),
                  onPressed: onEnd,
                  child: const Text('End session'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangedPanel extends StatelessWidget {
  const _ChangedPanel({required this.controller});

  final SessionFlowController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('changed-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'The camera or screen changed. Please calibrate again.',
                    key: const Key('changed-message'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'What you have done so far is kept. The calibration only fits the '
              'camera and screen it was made on.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('back-to-calibration'),
              onPressed: controller.recalibrate,
              child: const Text('Back to calibration'),
            ),
          ],
        ),
      ),
    );
  }
}
