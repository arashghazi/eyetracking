import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/pilot_repository.dart';

/// The settings versions of one study, newest first, with what each changed
/// against the version before it.
class SettingsHistoryController extends SafeChangeNotifier {
  SettingsHistoryController(this._repository, this.studyId);

  final PilotRepository _repository;
  final int studyId;

  List<SettingsVersion> _items = const [];
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;

  List<SettingsVersion> get items => _items;
  bool get loading => _loading;
  bool get loadedOnce => _loadedOnce;
  String? get error => _error;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await _repository.settingsHistory(studyId);
      _loadedOnce = true;
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// The values that [index] changed against the next older entry. The oldest
  /// entry has no earlier version to compare with.
  List<SettingChange> changesOf(int index) => index + 1 < _items.length
      ? _items[index].values.changesFrom(_items[index + 1].values)
      : const [];
}
