import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum BannerKind { error, info, success }

/// Non-blocking inline message. Shown at the top of a screen instead of a
/// modal dialog so the user can keep working; announced to screen readers.
class MessageBanner extends StatelessWidget {
  const MessageBanner({
    super.key,
    required this.message,
    this.kind = BannerKind.error,
    this.onDismiss,
  });

  final String message;
  final BannerKind kind;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, icon) = switch (kind) {
      BannerKind.error => (
          AppColors.errorTint,
          AppColors.error,
          Icons.error_outline,
        ),
      BannerKind.info => (
          AppColors.tealTint,
          AppColors.tealDark,
          Icons.info_outline,
        ),
      BannerKind.success => (
          AppColors.successTint,
          AppColors.success,
          Icons.check_circle_outline,
        ),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(kRadius),
          border: Border.all(color: foreground.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: foreground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: foreground),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                tooltip: 'Dismiss',
                onPressed: onDismiss,
                icon: Icon(Icons.close, size: 18, color: foreground),
              ),
          ],
        ),
      ),
    );
  }
}
