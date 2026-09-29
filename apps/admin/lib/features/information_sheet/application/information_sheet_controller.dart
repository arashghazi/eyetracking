import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/information_sheet_repository.dart';

/// Edits the five sections of a study's information sheet.
class InformationSheetController extends SafeChangeNotifier {
  InformationSheetController(this._repository, this.studyId);

  final InformationSheetRepository _repository;
  final int studyId;

  InformationSheet? _current;
  SheetContent _draft = const SheetContent();
  bool _loading = false;
  bool _loaded = false;
  bool _publishing = false;
  String? _error;
  String? _notice;

  /// The published sheet, or null when none exists yet.
  InformationSheet? get current => _current;
  SheetContent get draft => _draft;
  bool get loading => _loading;
  bool get loaded => _loaded;
  bool get publishing => _publishing;
  String? get error => _error;
  String? get notice => _notice;

  bool get canPublish => _draft.isComplete && !_publishing;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _current = await _repository.current(studyId);
      _draft = _current?.content ?? const SheetContent();
      _loaded = true;
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void edit({
    String? aims,
    String? discomfortSources,
    String? benefits,
    String? dataHandling,
    String? stopRules,
  }) {
    _draft = SheetContent(
      aims: aims ?? _draft.aims,
      discomfortSources: discomfortSources ?? _draft.discomfortSources,
      benefits: benefits ?? _draft.benefits,
      dataHandling: dataHandling ?? _draft.dataHandling,
      stopRules: stopRules ?? _draft.stopRules,
    );
    _notice = null;
    notifyListeners();
  }

  Future<bool> publish() async {
    if (!canPublish) return false;
    _publishing = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      _current = await _repository.publish(studyId, _draft);
      _notice = 'Version ${_current!.version} is now published.';
      return true;
    } catch (e) {
      _error = userMessage(e);
      return false;
    } finally {
      _publishing = false;
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
