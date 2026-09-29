import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

/// "Not evaluable" unless a passed validation made the eye region readable.
String eyeAttentionText(EyeRegionAttention eye) =>
    eye.evaluable && eye.share != null
        ? formatPercent(eye.share)
        : 'Not evaluable';

/// Marks a session recorded with the development estimator.
class SyntheticBadge extends StatelessWidget {
  const SyntheticBadge({super.key, required this.synthetic});

  final bool synthetic;

  @override
  Widget build(BuildContext context) {
    if (!synthetic) return const Text('Real');
    return Container(
      key: const Key('synthetic-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.warningTint,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
      ),
      child: const Text(
        'Synthetic',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.warning,
        ),
      ),
    );
  }
}

/// Passed, failed or "-" when no validation ran; icon and text, never colour
/// alone.
class ValidationBadge extends StatelessWidget {
  const ValidationBadge({super.key, required this.passed});

  final bool? passed;

  @override
  Widget build(BuildContext context) {
    if (passed == null) return const Text('—');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          passed! ? Icons.check_circle_outline : Icons.cancel_outlined,
          size: 18,
          color: passed! ? AppColors.success : AppColors.warning,
        ),
        const SizedBox(width: 6),
        Text(passed! ? 'Passed' : 'Failed'),
      ],
    );
  }
}
