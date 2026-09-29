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

/// The quality grade of a session: an icon and a word (never colour alone),
/// the reasons as a tooltip and the first reason as a small label.
class QualityBadge extends StatelessWidget {
  const QualityBadge({super.key, required this.quality, this.compact = true});

  final SessionQuality? quality;

  /// In a table cell the reasons are summarised in one small line.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final q = quality;
    if (q == null) return const Text('—');
    final (color, tint, icon) = switch (q.grade) {
      QualityGrade.ok => (
          AppColors.success,
          AppColors.successTint,
          Icons.check_circle_outline,
        ),
      QualityGrade.exclude => (
          AppColors.error,
          AppColors.errorTint,
          Icons.block,
        ),
      _ => (
          AppColors.warning,
          AppColors.warningTint,
          Icons.error_outline,
        ),
    };
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(
            qualityGradeLabel(q.grade),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
    final small = q.isOk ? '' : q.shortReason;
    return Tooltip(
      message: q.reasonsText,
      waitDuration: const Duration(milliseconds: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          chip,
          if (small.isNotEmpty && compact)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  small,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
