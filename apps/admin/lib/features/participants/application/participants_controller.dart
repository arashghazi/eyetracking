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
  bool _deleting = false;
  int _dataVersion = 0;
  String? _error;
  String? _notice;
  String? _identityEmail;
  String? _identityMessage;

  ParticipantRecord get record => _record;
  bool get loading => _loading;
  bool get revealing => _revealing;
  bool get deleting => _deleting;
  String? get error => _error;

  /// Counts completed deletions; sections that hold their own data (the
  /// assignments) reload when it changes.
  int get dataVersion => _dataVersion;

  /// A confirmation, for example after the research data was deleted.
  String? get notice => _notice;

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

  /// Deletes this participant's research data. [confirm] is what the
  /// researcher typed and must be exactly the research code.
  Future<bool> deleteData(String confirm) async {
    final code = _record.code;
    if (_deleting) return false;
    if (confirm.trim() != code) {
      _error = 'Type the research code $code exactly to delete the data.';
      notifyListeners();
      return false;
    }
    _deleting = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      final result = await _repository.deleteData(studyId, code, code);
      // The account and the code stay; what remains is an empty record.
      _record = await _repository.get(studyId, code);
      _identityEmail = null;
      _identityMessage = null;
      _dataVersion++;
      _notice = _deletedText(code, result);
      return true;
    } catch (e) {
      _error = userMessage(e);
      return false;
    } finally {
      _deleting = false;
      notifyListeners();
    }
  }

  static String _deletedText(String code, EraseResult result) {
    final parts = [
      for (final e in result.deleted.entries)
        if (e.value > 0) '${e.value} ${e.key}',
    ];
    return 'The research data of $code was deleted'
        '${parts.isEmpty ? '' : ' (${parts.join(', ')})'}. '
        'The account and the research code remain.';
  }

  void dismissNotice() {
    _notice = null;
    notifyListeners();
  }
}
