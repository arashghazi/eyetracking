import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../application/session_flow_controller.dart';
import '../domain/session_step.dart';
import 'camera_check_step.dart';
import 'intro_step.dart';
import 'session_top_bar.dart';
import 'stimulus_steps.dart';
import 'summary_step.dart';

/// The guided session, one step at a time. Pass a [controller] in tests;
/// otherwise one is built from the app dependencies.
class SessionFlowScreen extends StatefulWidget {
  const SessionFlowScreen({super.key, this.controller, this.assignment});

  final SessionFlowController? controller;

  /// The assignment to run; null for a measurement-only session.
  final Assignment? assignment;

  @override
  State<SessionFlowScreen> createState() => _SessionFlowScreenState();
}

class _SessionFlowScreenState extends State<SessionFlowScreen> {
  late final SessionFlowController _controller;
  late final bool _owns;

  @override
  void initState() {
    super.initState();
    final provided = widget.controller;
    if (provided != null) {
      _controller = provided;
      _owns = false;
    } else {
      final deps = AppScope.read(context);
      _controller = SessionFlowController(
        repository: deps.sessions,
        gaze: deps.gaze,
        frames: deps.frameSource,
        device: deps.device,
        assignment: widget.assignment,
        assignments: deps.assignments,
        profile: deps.profile,
        live: deps.live,
        speech: deps.speech,
        audioRecorder: deps.audioRecorder,
      );
      _owns = true;
    }
    if (_controller.step == SessionStep.intro && !_controller.introReady) {
      _controller.loadIntro();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _controller.updateScreen(ScreenInfo(
      w: media.size.width,
      h: media.size.height,
      dpr: media.devicePixelRatio,
    ));
  }

  @override
  void dispose() {
    if (_owns) _controller.dispose();
    super.dispose();
  }

  void _home() => Navigator.of(context).pop();

  Future<void> _confirmEnd() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End the session?'),
        content: const Text(
          'What you have done so far is kept. You can start a new session '
          'whenever you like.',
        ),
        actions: [
          TextButton(
            key: const Key('end-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            key: const Key('end-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End session'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _controller.endEarly();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        final controls = c.step.hasSessionControls;
        return PopScope(
          canPop: !c.hasActiveSession,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmEnd();
          },
          child: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(child: _body(c)),
                if (controls)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: SessionTopBar(controller: c, onEnd: _confirmEnd),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _body(SessionFlowController c) => switch (c.step) {
        SessionStep.intro => IntroStep(controller: c, onHome: _home),
        SessionStep.cameraCheck => CameraCheckStep(controller: c),
        SessionStep.summary => SummaryStep(controller: c, onHome: _home),
        _ => StimulusStepBody(controller: c, onEnd: _confirmEnd),
      };
}
