import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/measurement_settings_repository.dart';

/// One numeric setting as the form shows it.
class SettingField {
  const SettingField(this.key, this.label, this.help, {this.integer = false});

  /// Wire name, also the key of validation errors.
  final String key;
  final String label;
  final String help;
  final bool integer;
}

/// The settings form of one study. Researchers edit; analysts only read.
class MeasurementSettingsController extends SafeChangeNotifier {
  MeasurementSettingsController(
    this._repository,
    this.studyId, {
    required this.canEdit,
  });

  static const fields = [
    SettingField(
      'validation_min_correct',
      'Minimum correct share',
      'Share of validation samples that must land in the expected region. 0 to 1.',
    ),
    SettingField(
      'validation_max_uncertain',
      'Maximum uncertain share',
      'Share of validation samples that may be uncertain. 0 to 1.',
    ),
    SettingField(
      'min_region_to_error_ratio',
      'Minimum region-to-error ratio',
      'Eye-region height divided by the calibration error. 1 or more.',
    ),
    SettingField(
      'gaze_conf_threshold',
      'Gaze confidence threshold',
      'Samples below this confidence count as uncertain. 0 to 1.',
    ),
    SettingField(
      'calibration_points',
      'Calibration points',
      'Number of dots in the calibration. 5 to 16.',
      integer: true,
    ),
  ];

  final MeasurementSettingsRepository _repository;
  final int studyId;
  final bool canEdit;

  MeasurementSettings? _saved;
  final Map<String, String> _text = {};
  bool _allowContinue = true;
  Map<String, String> _errors = const {};
  bool _loading = false;
  bool _saving = false;
  bool _dirty = false;
  String? _error;
  String? _notice;

  /// The longest rationale the server takes.
  static const maxRationaleChars = 1000;

  MeasurementSettings? get saved => _saved;
  bool get loaded => _saved != null;

  /// The settings version on the server (1 = defaults).
  int get version => _saved?.version ?? 1;

  /// The form holds edits that are not saved.
  bool get dirty => _dirty;
  bool get loading => _loading;
  bool get saving => _saving;
  String? get error => _error;
  String? get notice => _notice;
  bool get allowContinueWithoutValidation => _allowContinue;

  /// Text currently in the field [key].
  String text(String key) => _text[key] ?? '';

  /// Validation message for [key], if any.
  String? errorFor(String key) => _errors[key];

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _apply(await _repository.load(studyId));
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Reads the settings again without the loading state, for when the tab
  /// comes back into view (a threshold review may have saved a new version).
  /// Edits that are not saved are left alone.
  Future<void> refresh() async {
    if (_dirty || _saving || _loading || isDisposed) return;
    try {
      final latest = await _repository.load(studyId);
      if (!_dirty && !_saving && !isDisposed) {
        _apply(latest);
        notifyListeners();
      }
    } catch (_) {
      // Keep showing what is there; the next load reports a problem.
    }
  }

  void _apply(MeasurementSettings s) {
    _saved = s;
    _dirty = false;
    final json = s.toJson();
    for (final f in fields) {
      _text[f.key] = _show(json[f.key]);
    }
    _allowContinue = s.allowContinueWithoutValidation;
    _errors = const {};
  }

  static String _show(Object? v) {
    if (v is double && v == v.roundToDouble()) return v.toStringAsFixed(1);
    return '$v';
  }

  void setText(String key, String value) {
    _text[key] = value;
    _dirty = true;
    if (_errors.containsKey(key)) {
      // Re-check only what is on screen so the message clears while typing.
      _errors = {..._errors}..remove(key);
    }
    _notice = null;
    notifyListeners();
  }

  void setAllowContinue(bool value) {
    _allowContinue = value;
    _dirty = true;
    _notice = null;
    notifyListeners();
  }

  /// Parses every field and checks the ranges. Sets the field errors, so all
  /// problems show at once.
  MeasurementSettings? _parse() {
    final parseErrors = <String, String>{};
    double number(String key) {
      final v = double.tryParse(text(key).trim().replaceAll(',', '.'));
      if (v == null || !v.isFinite) {
        parseErrors[key] = 'Enter a number.';
        return double.nan;
      }
      return v;
    }

    final pointsRaw = number('calibration_points');
    var points = -1;
    if (!pointsRaw.isNaN) {
      if (pointsRaw != pointsRaw.roundToDouble()) {
        parseErrors['calibration_points'] = 'Enter a whole number.';
      } else {
        points = pointsRaw.round();
      }
    }
    final candidate = MeasurementSettings(
      validationMinCorrect: number('validation_min_correct'),
      validationMaxUncertain: number('validation_max_uncertain'),
      minRegionToErrorRatio: number('min_region_to_error_ratio'),
      gazeConfThreshold: number('gaze_conf_threshold'),
      calibrationPoints: points,
      allowContinueWithoutValidation: _allowContinue,
    );
    // Unparseable values become NaN or -1, so the range check flags them too;
    // the parse message is the more helpful one and wins.
    _errors = {...candidate.validate(), ...parseErrors};
    return _errors.isEmpty ? candidate : null;
  }

  /// Checks the form without saving; true when every value is acceptable.
  bool validate() {
    final ok = _parse() != null;
    notifyListeners();
    return ok;
  }

  /// Saves the form. [rationale] (optional, at most [maxRationaleChars])
  /// says why; the server keeps it with the new settings version.
  Future<bool> save({String? rationale}) async {
    if (!canEdit || _saving) return false;
    _error = null;
    _notice = null;
    final parsed = _parse();
    if (parsed == null) {
      _error = 'Some values are not valid. Fix the marked fields and save again.';
      notifyListeners();
      return false;
    }
    _saving = true;
    notifyListeners();
    try {
      _apply(await _repository.save(studyId, parsed, rationale: rationale));
      _notice = 'Measurement settings saved.';
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
