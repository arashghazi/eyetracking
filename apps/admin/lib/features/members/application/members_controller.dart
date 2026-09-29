import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/members_repository.dart';

class MembersController extends SafeChangeNotifier {
  MembersController(this._repository, this.studyId);

  static const minPasswordLength = 8;

  final MembersRepository _repository;
  final int studyId;

  bool _busy = false;
  String? _error;
  String? _notice;
  StaffAccount? _lastCreated;

  bool get busy => _busy;
  String? get error => _error;
  String? get notice => _notice;

  /// The staff account created most recently in this session.
  StaffAccount? get lastCreated => _lastCreated;

  Future<bool> addMember({
    required String userId,
    required StudyRole studyRole,
    required bool canLinkIdentity,
  }) async {
    final id = int.tryParse(userId.trim());
    if (id == null || id < 1) {
      _error = 'Enter the numeric user id of the account to add.';
      notifyListeners();
      return false;
    }
    return _run(() async {
      await _repository.addMember(
        studyId: studyId,
        userId: id,
        studyRole: studyRole,
        canLinkIdentity: canLinkIdentity,
      );
      _notice = 'User $id was added as ${studyRole.label.toLowerCase()}'
          '${canLinkIdentity ? ' with the identity-link permission' : ''}.';
    });
  }

  Future<bool> createStaff({
    required String email,
    required String password,
    required StaffRole role,
  }) async {
    if (!email.contains('@')) {
      _error = 'Enter a valid email address.';
      notifyListeners();
      return false;
    }
    if (password.length < minPasswordLength) {
      _error = 'The password needs at least $minPasswordLength characters.';
      notifyListeners();
      return false;
    }
    return _run(() async {
      final account = await _repository.createStaff(
        email: email.trim(),
        password: password,
        role: role,
      );
      _lastCreated = account;
      _notice = 'Account created for ${account.email} '
          '(user id ${account.id}, ${account.role}).';
    });
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }

  void dismissNotice() {
    _notice = null;
    notifyListeners();
  }

  Future<bool> _run(Future<void> Function() action) async {
    _busy = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (e) {
      _error = userMessage(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
