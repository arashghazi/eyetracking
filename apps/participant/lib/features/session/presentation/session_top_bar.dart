import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../application/session_flow_controller.dart';
import '../domain/session_step.dart';
import '../domain/stimulus_geometry.dart';
import 'step_list.dart';

/// Thin bar over the stimulus screens: the step list, Pause and End session.
class SessionTopBar extends StatelessWidget {
  const SessionTopBar({super.key, required this.controller, required this.onEnd});

  final SessionFlowController controller;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final paused = c.phase == StepPhase.paused;
    final ButtonStyle style = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      child: Container(
        key: const Key('session-bar'),
        height: kControlBarHeight,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= (c.hasProtocol ? 1000 : 760);
          final medium = constraints.maxWidth >= 480;
          return Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (wide)
                          StepList(current: c.step, protocol: c.hasProtocol)
                        else ...[
                          StepList(
                            current: c.step,
                            compact: true,
                            protocol: c.hasProtocol,
                          ),
                          if (medium) ...[
                            const SizedBox(width: 8),
                            Text(
                              c.step.label,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (paused)
                TextButton.icon(
                  key: const Key('resume'),
                  style: style,
                  onPressed: c.canResume ? c.resume : null,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Resume'),
                )
              else
                TextButton.icon(
                  key: const Key('pause'),
                  style: style,
                  onPressed: c.canPause ? c.pause : null,
                  icon: const Icon(Icons.pause, size: 18),
                  label: const Text('Pause'),
                ),
              TextButton.icon(
                key: const Key('end-session'),
                style: style.merge(
                  TextButton.styleFrom(foregroundColor: AppColors.error),
                ),
                onPressed: c.canEnd ? onEnd : null,
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: Text(medium ? 'End session' : 'End'),
              ),
            ],
          );
        }),
      ),
    );
  }
}
