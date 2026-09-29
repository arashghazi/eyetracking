import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/participants_repository.dart';

class ParticipantsController extends SafeChangeNotifier {
  ParticipantsController(this._repository, this.studyId);

  final ParticipantsRepository _repository;
  final int studyId;

  List<ParticipantRecord> _records = const [];
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;

  List<ParticipantRecord> get records => _records;
  bool get loading => _loading;
  bool get loadedOnce => _loadedOnce;
  String? get error => _error;

  int get readyCount => _records.where((r) => r.readiness.ready).length;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _records = await _repository.list(studyId);
      _loadedOnce = true;
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }
}

/// One participant's detail, with the guarded identity reveal.
class ParticipantDetailController extends SafeChangeNotifier {
  ParticipantDetailController(
    this._repository,
    this.studyId,
    ParticipantRecord initial,
  ) : _record = initial;

  final ParticipantsRepository _repository;
  final int studyId;

  ParticipantRecord _record;
  bool _loading = false;
  bool _revealing = false;
  String? _error;
  String? _identityEmail;
  String? _identityMessage;

  ParticipantRecord get record => _record;
  bool get loading => _loading;
  bool get revealing => _revealing;
  String? get error => _error;

  /// The revealed login email, once fetched.
  String? get identityEmail => _identityEmail;

  /// Why the identity could not be shown (for example a missing grant).
  String? get identityMessage => _identityMessage;

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _record = await _repository.get(studyId, _record.code);
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> revealIdentity() async {
    _revealing = true;
    _identityMessage = null;
    notifyListeners();
    try {
      _identityEmail = await _repository.identity(studyId, _record.code);
    } on ApiException catch (e) {
      _identityEmail = null;
      _identityMessage = e.isForbidden
          ? 'You do not have permission to see participant identities in this '
              'study. An administrator can grant the identity-link permission.'
          : e.message;
    } catch (e) {
      _identityEmail = null;
      _identityMessage = userMessage(e);
    } finally {
      _revealing = false;
      notifyListeners();
    }
  }

  void hideIdentity() {
    _identityEmail = null;
    _identityMessage = null;
    notifyListeners();
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }
}
