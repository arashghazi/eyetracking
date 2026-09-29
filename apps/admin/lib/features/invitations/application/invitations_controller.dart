import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/invitation.dart';
import '../domain/invitations_repository.dart';

class InvitationsController extends SafeChangeNotifier {
  InvitationsController(this._repository, this.studyId);

  static const defaultExpiresDays = 14;
  static const maxExpiresDays = 90;

  final InvitationsRepository _repository;
  final int studyId;

  final List<Invitation> _created = [];
  bool _busy = false;
  String? _error;
  String? _notice;

  /// Invitations created in this session, newest first. Kept in memory only.
  List<Invitation> get created => List.unmodifiable(_created);
  bool get busy => _busy;
  String? get error => _error;
  String? get notice => _notice;

  /// Validates the form values and creates an invitation.
  Future<bool> create({required String email, required String expiresDays}) async {
    final trimmed = email.trim();
    if (trimmed.isNotEmpty && !trimmed.contains('@')) {
      _error = 'Enter a valid email address or leave it empty.';
      notifyListeners();
      return false;
    }
    final days = int.tryParse(expiresDays.trim());
    if (days == null || days < 1 || days > maxExpiresDays) {
      _error = 'Days until expiry must be a whole number from 1 to $maxExpiresDays.';
      notifyListeners();
      return false;
    }
    _busy = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      final invitation = await _repository.create(
        studyId,
        inviteeEmail: trimmed.isEmpty ? null : trimmed,
        expiresDays: days,
      );
      _created.insert(0, invitation);
      return true;
    } catch (e) {
      _error = userMessage(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void showNotice(String message) {
    _notice = message;
    notifyListeners();
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }

  void dismissNotice() {
    _notice = null;
    notifyListeners();
  }
}
