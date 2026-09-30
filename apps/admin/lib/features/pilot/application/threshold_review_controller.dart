import 'package:eyetracking_core/eyetracking_core.dart';

import '../../measurement_settings/domain/measurement_settings_repository.dart';
import '../domain/pilot_repository.dart';
import 'number_input.dart';
import 'settings_history_controller.dart';

/// One threshold a researcher can try in a review.
class CandidateField {
  const CandidateField(this.key, this.label, this.help, {this.atLeastOne = false});

  /// Wire name, also the key of the field errors.
  final String key;
  final String label;
  final String help;

  /// The region-to-error ratio needs 1 or more; the others are shares 0 to 1.
  final bool atLeastOne;

  String? check(double value) {
    if (atLeastOne) return value < 1 ? 'Enter a value of 1 or more.' : null;
    return value < 0 || value > 1 ? 'Enter a value from 0 to 1.' : null;
  }
}

/// The Thresholds section: try candidate thresholds on the recorded sessions
/// (saves nothing), then, as a researcher, save them as a new settings version
/// with a rationale.
class ThresholdReviewController extends SafeChangeNotifier {
  ThresholdReviewController(
    this._pilot,
    this._settings,
    this.studyId, {
    required this.canEdit,
  }) : history = SettingsHistoryController(_pilot, studyId);

  /// The fewest characters the rationale of a new version needs.
  static const minRationaleChars = 10;
  static const maxRationaleChars = 1000;

  static const fields = [
    CandidateField(
      'validation_min_correct',
      'Minimum correct share',
      'Validation samples that must land in the expected region. 0 to 1.',
    ),
    CandidateField(
      'validation_max_uncertain',
      'Maximum uncertain share',
      'Validation samples that may be uncertain. 0 to 1.',
    ),
    CandidateField(
      'min_region_to_error_ratio',
      'Minimum region-to-error ratio',
      'Eye-region height divided by the calibration error. 1 or more.',
      atLeastOne: true,
    ),
    CandidateField(
      'gaze_conf_threshold',
      'Gaze confidence threshold',
      'Applies to new sessions only. 0 to 1.',
    ),
    CandidateField(
      'quality_max_uncertain_share',
      'Quality: maximum uncertain share',
      'Above this a session is graded Review. 0 to 1.',
    ),
    CandidateField(
      'quality_max_missing_share',
      'Quality: maximum missing share',
      'Above this a session is graded Review. 0 to 1.',
    ),
  ];

  final PilotRepository _pilot;
  final MeasurementSettingsRepository _settings;
  final int studyId;
  final bool canEdit;

  /// The settings versions, shown below the review.
  final SettingsHistoryController history;

  MeasurementSettings? _current;
  final Map<String, String> _text = {};
  Map<String, String> _errors = const {};
  bool _includeSynthetic = false;
  bool _loading = false;
  bool _loadedOnce = false;
  bool _reviewing = false;
  bool _saving = false;
  ThresholdReview? _review;
  Map<String, dynamic> _reviewedChanges = const {};
  bool _stale = false;
  int _epoch = 0;
  String? _error;
  String? _saveError;
  String? _notice;

  /// Counts the times the candidate fields were filled by the controller (a
  /// load, a reset, a saved version), so the fields show the new text.
  int get epoch => _epoch;

  MeasurementSettings? get current => _current;
  int get version => _current?.version ?? 1;
  bool get loading => _loading;
  bool get loadedOnce => _loadedOnce;
  bool get reviewing => _reviewing;
  bool get saving => _saving;
  bool get includeSynthetic => _includeSynthetic;

  /// The result of the last review, or null before one (or after a change
  /// that makes it out of date).
  ThresholdReview? get review => _review;

  /// The candidate values changed after the last review, so what it shows is
  /// not what would be saved.
  bool get stale => _stale;
  String? get error => _error;
  String? get saveError => _saveError;
  String? get notice => _notice;

  /// The fields the last review tried.
  Map<String, dynamic> get reviewedChanges => _reviewedChanges;

  bool get canSave =>
      canEdit &&
      !_saving &&
      _review != null &&
      !_stale &&
      _reviewedChanges.isNotEmpty;

  String text(String key) => _text[key] ?? '';
  String? errorFor(String key) => _errors[key];

  /// The current value of a candidate field, as text.
  String currentText(String key) => formatSettingValue(_valueOf(_current, key));

  static double? _valueOf(MeasurementSettings? s, String key) => switch (key) {
        'validation_min_correct' => s?.validationMinCorrect,
        'validation_max_uncertain' => s?.validationMaxUncertain,
        'min_region_to_error_ratio' => s?.minRegionToErrorRatio,
        'gaze_conf_threshold' => s?.gazeConfThreshold,
        'quality_max_uncertain_share' => s?.qualityMaxUncertainShare,
        'quality_max_missing_share' => s?.qualityMaxMissingShare,
        _ => null,
      };

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _applyCurrent(await _settings.load(studyId));
      _loadedOnce = true;
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
    await history.load();
  }

  void _applyCurrent(MeasurementSettings s) {
    _current = s;
    _epoch++;
    for (final f in fields) {
      _text[f.key] = formatSettingValue(_valueOf(s, f.key));
    }
    _errors = const {};
  }

  void setText(String key, String value) {
    _text[key] = value;
    if (_errors.containsKey(key)) _errors = {..._errors}..remove(key);
    if (_review != null) _stale = true;
    _notice = null;
    notifyListeners();
  }

  /// Puts every candidate field back to the current value.
  void resetCandidates() {
    final s = _current;
    if (s != null) _applyCurrent(s);
    if (_review != null) _stale = true;
    notifyListeners();
  }

  void setIncludeSynthetic(bool value) {
    if (value == _includeSynthetic) return;
    _includeSynthetic = value;
    // The sessions in the result depend on it.
    _review = null;
    _stale = false;
    _reviewedChanges = const {};
    notifyListeners();
  }

  /// The fields whose text differs from the current value, or null when a
  /// field is not a valid number in range (the errors are then set).
  Map<String, dynamic>? _changes() {
    final errors = <String, String>{};
    final changes = <String, dynamic>{};
    for (final f in fields) {
      final value = parseDecimal(text(f.key));
      if (value == null) {
        errors[f.key] = 'Enter a number.';
        continue;
      }
      final problem = f.check(value);
      if (problem != null) {
        errors[f.key] = problem;
        continue;
      }
      if (value != _valueOf(_current, f.key)) changes[f.key] = value;
    }
    _errors = errors;
    return errors.isEmpty ? changes : null;
  }

  /// "Review": what the candidate thresholds would change. Saves nothing.
  Future<void> runReview() async {
    if (_reviewing || _current == null) return;
    _error = null;
    _saveError = null;
    _notice = null;
    final changes = _changes();
    if (changes == null) {
      _error = 'Some values are not valid. Fix the marked fields and review again.';
      notifyListeners();
      return;
    }
    _reviewing = true;
    notifyListeners();
    try {
      _review = await _pilot.thresholdReview(
        studyId,
        changes: changes,
        includeSynthetic: _includeSynthetic,
      );
      _reviewedChanges = changes;
      _stale = false;
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _reviewing = false;
      notifyListeners();
    }
  }

  /// What "Save as new settings version" would change: the reviewed fields
  /// with the current and the candidate value.
  List<SettingChange> get pendingChanges => [
        for (final e in _reviewedChanges.entries)
          SettingChange(
            key: e.key,
            before: _valueOf(_current, e.key),
            after: e.value,
          ),
      ];

  /// Saves the reviewed candidate as the next settings version. [rationale]
  /// (at least [minRationaleChars] characters) says why. Returns whether the
  /// server took it.
  Future<bool> saveAsVersion(String rationale) async {
    if (!canSave) return false;
    final why = rationale.trim();
    if (why.length < minRationaleChars) {
      _saveError = 'Give a rationale of at least $minRationaleChars characters.';
      notifyListeners();
      return false;
    }
    if (why.length > maxRationaleChars) {
      _saveError = 'The rationale is limited to $maxRationaleChars characters.';
      notifyListeners();
      return false;
    }
    _saving = true;
    _saveError = null;
    _error = null;
    notifyListeners();
    try {
      final saved = await _settings.saveChanges(
        studyId,
        Map<String, dynamic>.of(_reviewedChanges),
        rationale: why,
      );
      _applyCurrent(saved);
      _review = null;
      _reviewedChanges = const {};
      _stale = false;
      _notice = 'Saved as settings version ${saved.version}.';
      await history.load();
      return true;
    } catch (e) {
      _saveError = userMessage(e);
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  void clearSaveError() {
    _saveError = null;
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

  @override
  void dispose() {
    history.dispose();
    super.dispose();
  }
}
