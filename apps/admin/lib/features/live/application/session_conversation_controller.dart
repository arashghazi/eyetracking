import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/live_models.dart';
import '../domain/live_repository.dart';

/// The conversation of one session for the session detail. A session without
/// one is the normal case for the other paths: [conversation] stays null and
/// nothing is shown.
class SessionConversationController extends SafeChangeNotifier {
  SessionConversationController(this._repository, this.studyId, this.sessionId);

  final LiveRepository _repository;
  final int studyId;
  final String sessionId;

  StaffConversation? _conversation;
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  StaffConversation? get conversation => _conversation;
  bool get loading => _loading;

  /// The read finished (with or without a conversation).
  bool get loaded => _loaded;

  /// The server's own wording of why the read failed (not a 404).
  String? get error => _error;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _conversation = await _repository.conversation(studyId, sessionId);
      _loaded = true;
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
