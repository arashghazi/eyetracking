import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

/// "Yes" or "No" with an icon, so the state is not conveyed by colour alone.
class YesNo extends StatelessWidget {
  const YesNo({super.key, required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          value ? Icons.check_circle_outline : Icons.remove_circle_outline,
          size: 18,
          color: value ? AppColors.success : AppColors.warning,
        ),
        const SizedBox(width: 6),
        Text(value ? 'Yes' : 'No'),
      ],
    );
  }
}
