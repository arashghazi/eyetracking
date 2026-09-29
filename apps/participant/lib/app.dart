import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import 'app_dependencies.dart';
import 'app_scope.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/presentation/accept_invitation_screen.dart';
import 'features/auth/presentation/sign_in_screen.dart';
import 'features/home/presentation/home_screen.dart';

class ParticipantApp extends StatelessWidget {
  const ParticipantApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      dependencies: dependencies,
      child: MaterialApp(
        title: 'EyeTracking practice',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: _AppRoot(dependencies: dependencies),
      ),
    );
  }
}

/// Shows the sign-in flow or the home screen depending on the session.
class _AppRoot extends StatefulWidget {
  const _AppRoot({required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  bool _wasSignedIn = false;

  @override
  void initState() {
    super.initState();
    _wasSignedIn = widget.dependencies.auth.isSignedIn;
    widget.dependencies.auth.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    widget.dependencies.auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  /// When the session ends while a step screen is open, return to the root.
  void _onAuthChanged() {
    final signedIn = widget.dependencies.auth.isSignedIn;
    if (_wasSignedIn && !signedIn && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    _wasSignedIn = signedIn;
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.dependencies.auth;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) => auth.isSignedIn
          ? HomeScreen(auth: auth)
          : _AuthFlow(
              auth: auth,
              initialToken: widget.dependencies.initialInvitationToken,
            ),
    );
  }
}

/// Switches between sign-in and invitation without pushing routes, so that
/// signing in simply replaces this widget with the home screen.
class _AuthFlow extends StatefulWidget {
  const _AuthFlow({required this.auth, required this.initialToken});

  final AuthController auth;
  final String initialToken;

  @override
  State<_AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends State<_AuthFlow> {
  late bool _invitation = widget.initialToken.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return _invitation
        ? AcceptInvitationScreen(
            auth: widget.auth,
            initialToken: widget.initialToken,
            onBack: () => setState(() => _invitation = false),
          )
        : SignInScreen(
            auth: widget.auth,
            onHaveInvitation: () => setState(() => _invitation = true),
          );
  }
}
