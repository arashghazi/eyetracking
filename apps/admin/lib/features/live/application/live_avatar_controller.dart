import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/live_models.dart';
import '../domain/live_repository.dart';

/// The "Live avatar" card of the AI tab: providers, estimates, the shared
/// budget and the open conversations of one study. Read-only; the cap is set
/// in the "Providers and budget" card above it.
class LiveAvatarController extends SafeChangeNotifier {
  LiveAvatarController(this._repository, this.studyId);

  final LiveRepository _repository;
  final int studyId;

  LiveAvatarStatus? _status;
  bool _loading = false;
  bool _unavailable = false;
  String? _error;

  LiveAvatarStatus? get status => _status;
  bool get loading => _loading;

  /// The server does not know the live endpoints (an older service): there is
  /// nothing to show.
  bool get unavailable => _unavailable;

  /// The server's own wording of why the status could not be read.
  String? get error => _error;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _status = await _repository.status(studyId);
      _unavailable = false;
    } on ApiException catch (e) {
      if (e.isNotFound) {
        _unavailable = true;
        _status = null;
      } else {
        _error = userMessage(e);
      }
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
