import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../ai/presentation/ai_widgets.dart' show StateChip;
import '../domain/live_models.dart';

/// The flags of a turn as small chips: distress in red, the flags that mean
/// the server replaced or refused something in amber, the rest outlined.
class FlagChips extends StatelessWidget {
  const FlagChips({super.key, required this.flags});

  final List<String> flags;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [for (final f in flags) _chip(f)],
      );

  static Widget _chip(String flag) {
    final label = conversationFlagLabel(flag);
    if (flag == 'distress') {
      return StateChip(
        label: label,
        foreground: AppColors.error,
        background: AppColors.errorTint,
        icon: Icons.priority_high,
      );
    }
    if (conversationFlagNeedsAttention(flag)) {
      return StateChip(
        label: label,
        foreground: AppColors.warning,
        background: AppColors.warningTint,
      );
    }
    return StateChip(label: label, foreground: AppColors.textMuted, outlined: true);
  }
}

/// "Participant" or "Avatar".
String conversationRoleLabel(String role) => switch (role) {
      'participant' => 'Participant',
      'avatar' => 'Avatar',
      _ => role.isEmpty ? '-' : role[0].toUpperCase() + role.substring(1),
    };
