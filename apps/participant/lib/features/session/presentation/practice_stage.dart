import 'package:flutter/widgets.dart';

import '../application/session_flow_controller.dart';
import 'gradual_practice_view.dart';
import 'interest_practice_view.dart';

/// The running practice (or the interest post video): dispatches to the view
/// of the path the protocol runs.
class PracticeStage extends StatelessWidget {
  const PracticeStage({super.key, required this.controller});

  final SessionFlowController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final interest = c.interest;
    if (c.isInterest && interest != null) {
      return InterestPracticeView(flow: c, controller: interest);
    }
    final gradual = c.gradual;
    if (gradual != null) return GradualPracticeView(flow: c, controller: gradual);
    return const SizedBox.shrink();
  }
}
