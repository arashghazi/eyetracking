import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/consent_repository.dart';

class ConsentController extends SafeChangeNotifier {
  ConsentController(this._repository);

  final ConsentRepository _repository;

  InformationSheet? _sheet;
  Consent? _consent;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _notice;

  bool _agree = false;
  bool _audio = false;
  bool _video = false;

  InformationSheet? get sheet => _sheet;
  Consent? get consent => _consent;
  bool get loading => _loading;
  bool get saving => _saving;
  String? get error => _error;
  String? get notice => _notice;

  bool get agree => _agree;
  bool get audio => _audio;
  bool get video => _video;

  /// Consent that covers the sheet currently on display.
  bool get hasActiveConsent {
    final sheet = _sheet;
    final consent = _consent;
    return sheet != null && consent != null && consent.isActiveFor(sheet.version);
  }

  /// True when an earlier consent exists but no longer applies.
  bool get hasStaleConsent =>
      _consent != null && _sheet != null && !hasActiveConsent;

  bool get canSubmit => _sheet != null && _agree && !_saving && !hasActiveConsent;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait<Object?>([
        _repository.fetchSheet(),
        _repository.fetchConsent(),
      ]);
      _sheet = results[0] as InformationSheet?;
      _consent = results[1] as Consent?;
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setAgree(bool value) {
    _agree = value;
    notifyListeners();
  }

  void setAudio(bool value) {
    _audio = value;
    notifyListeners();
  }

  void setVideo(bool value) {
    _video = value;
    notifyListeners();
  }

  Future<bool> submit() async {
    final sheet = _sheet;
    if (!canSubmit || sheet == null) return false;
    return _save(() async {
      _consent = await _repository.give(
        sheetVersion: sheet.version,
        participate: true,
        audioRecording: _audio,
        videoRecording: _video,
      );
      _notice = 'Your consent has been recorded.';
    });
  }

  Future<bool> withdraw() => _save(() async {
        _consent = await _repository.withdraw();
        _agree = false;
        _audio = false;
        _video = false;
        _notice = 'Your consent has been withdrawn. You can give it again at any time.';
      });

  void dismissError() {
    _error = null;
    notifyListeners();
  }

  void dismissNotice() {
    _notice = null;
    notifyListeners();
  }

  Future<bool> _save(Future<void> Function() action) async {
    _saving = true;
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
      _saving = false;
      notifyListeners();
    }
  }
}
