import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

const Color _blue = Color(0xFF1F5FA8);
const Color _blueTint = Color(0xFFE4EEF9);
const Color _greyTint = Color(0xFFEAEDED);

/// Small square-cornered label used for job and provider states.
class StateChip extends StatelessWidget {
  const StateChip({
    super.key,
    required this.label,
    required this.foreground,
    this.background,
    this.outlined = false,
    this.icon,
  });

  final String label;
  final Color foreground;
  final Color? background;
  final bool outlined;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: outlined ? null : background,
          border: outlined ? Border.all(color: foreground) : null,
          borderRadius: BorderRadius.circular(kRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      );
}

/// queued grey, running blue, succeeded green, failed red, cancelled outlined.
class JobStatusChip extends StatelessWidget {
  const JobStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = aiJobStatusLabel(status);
    return switch (status) {
      AiJobStatus.queued => StateChip(
          label: label,
          foreground: AppColors.textMuted,
          background: _greyTint,
        ),
      AiJobStatus.running => StateChip(
          label: label,
          foreground: _blue,
          background: _blueTint,
        ),
      AiJobStatus.succeeded => StateChip(
          label: label,
          foreground: AppColors.success,
          background: AppColors.successTint,
        ),
      AiJobStatus.failed => StateChip(
          label: label,
          foreground: AppColors.error,
          background: AppColors.errorTint,
        ),
      _ => StateChip(
          label: label,
          foreground: AppColors.textMuted,
          outlined: true,
        ),
    };
  }
}

/// "Configured" or "Not configured".
class ConfiguredChip extends StatelessWidget {
  const ConfiguredChip({super.key, required this.configured});

  final bool configured;

  @override
  Widget build(BuildContext context) => configured
      ? const StateChip(
          label: 'Configured',
          foreground: AppColors.success,
          background: AppColors.successTint,
          icon: Icons.check_circle_outline,
        )
      : const StateChip(
          label: 'Not configured',
          foreground: AppColors.warning,
          background: AppColors.warningTint,
          icon: Icons.warning_amber_outlined,
        );
}

/// Shown for the fake development provider.
class SyntheticBadge extends StatelessWidget {
  const SyntheticBadge({super.key});

  static const text = 'Development provider — sample content';

  @override
  Widget build(BuildContext context) => const StateChip(
        label: text,
        foreground: _blue,
        background: _blueTint,
        icon: Icons.science_outlined,
      );
}

/// A short caption in the muted colour.
class MutedText extends StatelessWidget {
  const MutedText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
}
