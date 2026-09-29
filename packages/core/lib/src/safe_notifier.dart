import 'package:flutter/foundation.dart';

import 'api/api_exception.dart';

/// [ChangeNotifier] that ignores notifications after disposal, so async
/// controller methods can finish safely after their screen has closed.
class SafeChangeNotifier extends ChangeNotifier {
  bool _disposed = false;

  bool get isDisposed => _disposed;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Text that is safe to show to the user for any thrown error.
String userMessage(Object error) => error is ApiException
    ? error.message
    : 'Something went wrong. Please try again.';
