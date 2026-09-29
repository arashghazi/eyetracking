import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/studies_repository.dart';
import '../domain/study.dart';

/// The retention policy of one study (administrators only).
class StudySettingsController extends SafeChangeNotifier {
  StudySettingsController(this._repository, this.studyId);

  final StudiesRepository _repository;
  final int studyId;

  Study? _study;
  String _draft = RetentionPolicy.deleteAll;
  bool _touched = false;
  bool _unreadable = false;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _notice;

  Study? get study => _study;

  /// The policy as chosen in the form (not necessarily saved).
  String get draft => _draft;
  bool get loading => _loading;
  bool get saving => _saving;
  String? get error => _error;
  String? get notice => _notice;

  /// True when the current policy could not be read because the administrator
  /// is not a member of the study (reading study settings needs a
  /// membership; setting the policy needs only the admin role).
  bool get unreadable => _unreadable;

  /// A policy is chosen: the saved one, or one picked when the saved policy
  /// could not be read.
  bool get hasChoice => _study != null || _touched;

  /// Something can be saved: the draft differs from the saved policy, or the
  /// saved policy is unknown and a policy was chosen.
  bool get changed => _study != null
      ? _draft != _study!.retentionPolicy
      : _unreadable && _touched;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final study = await _repository.get(studyId);
      _study = study;
      _draft = study.retentionPolicy;
      _unreadable = false;
    } on ApiException catch (e) {
      if (e.isForbidden) {
        _unreadable = true;
      } else {
        _error = e.message;
      }
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void choose(String policy) {
    if (!RetentionPolicy.all.contains(policy)) return;
    if (policy == _draft && (_study != null || _touched)) return;
    _draft = policy;
    _touched = true;
    _notice = null;
    notifyListeners();
  }

  Future<bool> save() async {
    if (_saving || !changed) return false;
    _saving = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      final study = await _repository.setRetentionPolicy(studyId, _draft);
      _study = study;
      _draft = study.retentionPolicy;
      _unreadable = false;
      _touched = false;
      _notice = 'Retention policy saved: '
          '${RetentionPolicy.label(study.retentionPolicy).toLowerCase()}.';
      return true;
    } catch (e) {
      _error = userMessage(e);
      return false;
    } finally {
      _saving = false;
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
}
