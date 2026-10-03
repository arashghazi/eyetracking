import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../application/session_flow_controller.dart';
import '../domain/session_step.dart';
import 'step_list.dart';

/// Preview of the camera and the quick face check.
class CameraCheckStep extends StatelessWidget {
  const CameraCheckStep({super.key, required this.controller});

  final SessionFlowController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final outcome = c.cameraOutcome;
    final muted = theme.colorScheme.onSurfaceVariant;

    return PageFrame(
      banner: c.error != null
          ? MessageBanner(message: c.error!, onDismiss: c.dismissError)
          : null,
      children: [
        Text('Camera check', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        const StepList(current: SessionStep.cameraCheck),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Position your face in the frame',
                  key: const Key('camera-instruction'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Sit about an arm\'s length from the screen with light on '
                  'your face, not behind you.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
                const SizedBox(height: 12),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(kRadius),
                            child: c.frameSource.preview(),
                          ),
                          const IgnorePointer(
                            child: CustomPaint(painter: _GuidePainter()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (c.frameSource.cameras.length > 1) ...[
                  const SizedBox(height: 16),
                  _CameraPicker(controller: c),
                ] else if (c.frameSource.cameras.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Camera: ${c.frameSource.activeCameraLabel ?? c.frameSource.cameras.first.label}',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
                const SizedBox(height: 12),
                if (outcome != null)
                  _Outcome(outcome: outcome)
                else if (c.busy)
                  Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text('Checking. Hold still for a moment.',
                          key: const Key('camera-checking'),
                          style: theme.textTheme.bodyMedium),
                    ],
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (outcome?.passed == true)
                      FilledButton(
                        key: const Key('camera-continue'),
                        onPressed: c.continueToCalibration,
                        child: const Text('Continue to calibration'),
                      ),
                    if (outcome?.passed == true)
                      OutlinedButton(
                        key: const Key('camera-run'),
                        onPressed: c.busy ? null : c.runCameraCheck,
                        child: const Text('Check again'),
                      )
                    else
                      FilledButton(
                        key: const Key('camera-run'),
                        onPressed: c.busy ? null : c.runCameraCheck,
                        child: Text(outcome == null ? 'Check camera' : 'Try again'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Choice between the cameras the browser reports. Rebuilt whenever the
/// camera in use changes, so a failed switch shows the camera still open.
class _CameraPicker extends StatelessWidget {
  const _CameraPicker({required this.controller});

  final SessionFlowController controller;

  @override
  Widget build(BuildContext context) {
    final source = controller.frameSource;
    final active = source.activeCameraId;
    final known = source.cameras.any((cam) => cam.id == active);
    return KeyedSubtree(
      key: ValueKey('camera-picker-$active-${controller.busy}'),
      child: DropdownButtonFormField<String>(
        key: const Key('camera-select'),
        initialValue: known ? active : null,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Camera',
          helperText: 'Choose the camera in front of you. This computer '
              'remembers your choice.',
        ),
        hint: const Text('Choose a camera'),
        items: [
          for (final cam in source.cameras)
            DropdownMenuItem(
              value: cam.id,
              child: Text(cam.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: controller.busy
            ? null
            : (id) {
                if (id != null) controller.selectCamera(id);
              },
      ),
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({required this.outcome});

  final CameraCheckOutcome outcome;

  @override
  Widget build(BuildContext context) {
    if (outcome.passed) {
      return MessageBanner(
        key: const Key('camera-passed'),
        kind: BannerKind.success,
        message: 'Your face was found in ${outcome.framesWithFace} of '
            '${outcome.framesSampled} pictures. The camera is ready.',
      );
    }
    return MessageBanner(
      key: const Key('camera-failed'),
      message: 'We could not see your face clearly enough (found in '
          '${outcome.framesWithFace} of ${outcome.framesSampled} pictures). '
          'Move to a place with more light, face the camera and try again.',
    );
  }
}

/// A soft oval showing where the face should be.
class _GuidePainter extends CustomPainter {
  const _GuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.height * 0.62,
      height: size.height * 0.84,
    );
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_GuidePainter old) => false;
}
