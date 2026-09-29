import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import 'app_dependencies.dart';
import 'app_scope.dart';
import 'features/auth/presentation/sign_in_screen.dart';
import 'features/studies/presentation/studies_screen.dart';

class ResearchAdminApp extends StatelessWidget {
  const ResearchAdminApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      dependencies: dependencies,
      child: MaterialApp(
        title: 'EyeTracking Research Admin',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: _AppRoot(dependencies: dependencies),
      ),
    );
  }
}

/// Shows sign-in or the studies list depending on the session.
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

  /// When the session ends while a study screen is open, return to the root.
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
          ? StudiesScreen(auth: auth)
          : SignInScreen(auth: auth),
    );
  }
}
