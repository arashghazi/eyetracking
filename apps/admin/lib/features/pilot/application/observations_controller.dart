import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/pilot_repository.dart';

/// The supervisor observations of one session and the form that adds one.
/// Observations cannot be edited or deleted; a correction is a new one.
class ObservationsController extends SafeChangeNotifier {
  ObservationsController(this._repository, this.studyId, this.sessionId);

  final PilotRepository _repository;
  final int studyId;
  final String sessionId;

  List<Observation> _items = const [];
  bool _loading = false;
  bool _loadedOnce = false;
  bool _saving = false;
  String? _error;
  String? _formError;
  String? _notice;

  /// Oldest first.
  List<Observation> get items => _items;
  bool get loading => _loading;
  bool get loadedOnce => _loadedOnce;
  bool get saving => _saving;

  /// Why the list could not be read (shown as the server wrote it).
  String? get error => _error;

  /// Why the last save was refused.
  String? get formError => _formError;
  String? get notice => _notice;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await _repository.observations(studyId, sessionId);
      _loadedOnce = true;
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Saves an observation. Returns whether the server took it.
  Future<bool> add({
    required String category,
    required String severity,
    required String text,
    int? tMs,
  }) async {
    if (_saving) return false;
    _notice = null;
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _formError = 'Write what you saw before saving.';
      notifyListeners();
      return false;
    }
    if (trimmed.length > kMaxObservationChars) {
      _formError = 'The note is limited to $kMaxObservationChars characters.';
      notifyListeners();
      return false;
    }
    _saving = true;
    _formError = null;
    notifyListeners();
    try {
      final created = await _repository.addObservation(
        studyId,
        sessionId,
        ObservationRequest(
          category: category,
          severity: severity,
          text: trimmed,
          tMs: tMs,
        ),
      );
      _items = [..._items, created];
      _loadedOnce = true;
      _notice = 'Observation saved.';
      return true;
    } catch (e) {
      _formError = userMessage(e);
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  void dismissFormError() {
    _formError = null;
    notifyListeners();
  }
}
