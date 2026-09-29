import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';

/// Runs a download: fetches the bytes, hands them to the browser and says
/// what happened. Shared by every screen that has an export button.
class DownloadController extends SafeChangeNotifier {
  DownloadController(this._save);

  final FileSaver _save;

  String? _busyLabel;
  String? _error;
  String? _notice;

  /// The name of the file being fetched, or null when idle.
  String? get busyLabel => _busyLabel;
  bool get busy => _busyLabel != null;
  String? get error => _error;
  String? get notice => _notice;

  /// Fetches with [fetch] and saves the result as [filename]. Returns true
  /// when the browser was handed the file.
  Future<bool> download(
    Future<Uint8List> Function() fetch, {
    required String filename,
    required String mimeType,
  }) async {
    if (busy) return false;
    _busyLabel = filename;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      final bytes = await fetch();
      final saved = await _save(bytes, filename, mimeType);
      if (saved) {
        _notice = 'Downloaded $filename (${_size(bytes.length)}).';
      } else {
        _error = 'Downloads are available in the web app.';
      }
      return saved;
    } catch (e) {
      _error = userMessage(e);
      return false;
    } finally {
      _busyLabel = null;
      notifyListeners();
    }
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }

  void dismissNotice() {
    _notice = null;
    notifyListeners();
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Media types of the downloads.
abstract final class DownloadTypes {
  static const csv = 'text/csv;charset=utf-8';
  static const json = 'application/json';
}
