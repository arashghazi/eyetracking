import 'package:flutter/widgets.dart';

import 'app_dependencies.dart';

/// Makes [AppDependencies] available to every screen, including routes pushed
/// on the navigator.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.dependencies,
    required super.child,
  });

  final AppDependencies dependencies;

  /// Reads the dependencies once, without subscribing (safe in initState).
  static AppDependencies read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above this widget');
    return scope!.dependencies;
  }

  /// Like [read], but null when there is no [AppScope] (a screen shown on
  /// its own in a test): optional features then stay out of the way.
  static AppDependencies? maybeRead(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()?.dependencies;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      dependencies != oldWidget.dependencies;
}
