import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/profile_repository.dart';

class ProfileController extends SafeChangeNotifier {
  ProfileController(this._repository);

  final ProfileRepository _repository;

  Profile _draft = const Profile();
  bool _loaded = false;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _notice;

  /// The profile as currently edited (not necessarily saved).
  Profile get draft => _draft;
  bool get loaded => _loaded;
  bool get loading => _loading;
  bool get saving => _saving;
  String? get error => _error;
  String? get notice => _notice;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _draft = await _repository.load();
      _loaded = true;
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setDisplayName(String value) => _edit(_draft.copyWith(displayName: value));
  void setVoicePreference(String value) =>
      _edit(_draft.copyWith(voicePreference: value));
  void setFacePreference(String value) =>
      _edit(_draft.copyWith(facePreference: value));
  void setResponseMode(ResponseMode value) =>
      _edit(_draft.copyWith(responseMode: value));
  void setSpeed(Speed value) => _edit(_draft.copyWith(speed: value));

  void addNeed(String text) {
    final value = _clean(text);
    if (value == null || _draft.accessibilityNeeds.contains(value)) return;
    _edit(_draft.copyWith(
      accessibilityNeeds: [..._draft.accessibilityNeeds, value],
    ));
  }

  void removeNeed(String value) => _edit(_draft.copyWith(
        accessibilityNeeds:
            _draft.accessibilityNeeds.where((e) => e != value).toList(),
      ));

  void addInterest(String text) {
    final value = _clean(text);
    if (value == null || _draft.interests.contains(value)) return;
    _edit(_draft.copyWith(interests: [..._draft.interests, value]));
  }

  void removeInterest(String value) => _edit(_draft.copyWith(
        interests: _draft.interests.where((e) => e != value).toList(),
      ));

  Future<bool> save() async {
    _saving = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      _draft = await _repository.save(_draft);
      _notice = 'Your profile has been saved.';
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

  void _edit(Profile next) {
    _draft = next;
    _notice = null;
    notifyListeners();
  }

  String? _clean(String text) {
    final value = text.trim();
    return value.isEmpty ? null : value;
  }
}
