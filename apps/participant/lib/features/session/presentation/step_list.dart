import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../domain/session_step.dart';

/// The visible list of steps: Camera check, Calibration, Validation,
/// Baseline, Summary. Done steps carry a tick, the current one is filled.
class StepList extends StatelessWidget {
  const StepList({super.key, required this.current, this.compact = false});

  final SessionStep current;

  /// Numbered squares only, for narrow bars.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final index = current.listIndex;
    final steps = SessionStep.listed;
    if (compact) {
      return Semantics(
        label: index < 0
            ? 'Before the first step'
            : 'Step ${index + 1} of ${steps.length}: ${current.label}',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              _Square(number: i + 1, state: _stateOf(i, index)),
            ],
          ],
        ),
      );
    }
    return Wrap(
      key: const Key('step-list'),
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          _Chip(label: steps[i].label, state: _stateOf(i, index)),
          if (i < steps.length - 1)
            const Icon(Icons.arrow_forward, size: 14, color: AppColors.textMuted),
        ],
      ],
    );
  }

  static _StepState _stateOf(int i, int index) => i < index
      ? _StepState.done
      : i == index
          ? _StepState.current
          : _StepState.upcoming;
}

enum _StepState { done, current, upcoming }

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.state});

  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final current = state == _StepState.current;
    final done = state == _StepState.done;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: current ? AppColors.teal : AppColors.surface,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(
          color: current
              ? AppColors.teal
              : done
                  ? AppColors.success.withValues(alpha: 0.5)
                  : AppColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (done) ...[
            const Icon(Icons.check, size: 14, color: AppColors.success),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: current ? FontWeight.w600 : FontWeight.w500,
              color: current
                  ? Colors.white
                  : done
                      ? AppColors.text
                      : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Square extends StatelessWidget {
  const _Square({required this.number, required this.state});

  final int number;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final current = state == _StepState.current;
    final done = state == _StepState.done;
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: current
            ? AppColors.teal
            : done
                ? AppColors.successTint
                : AppColors.surface,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(
          color: current
              ? AppColors.teal
              : done
                  ? AppColors.success
                  : AppColors.border,
        ),
      ),
      child: done
          ? const Icon(Icons.check, size: 14, color: AppColors.success)
          : Text(
              '$number',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: current ? Colors.white : AppColors.textMuted,
              ),
            ),
    );
  }
}
