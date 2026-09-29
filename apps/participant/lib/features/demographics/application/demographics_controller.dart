import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/demographics_repository.dart';

/// Edits the answers to the study's configurable demographics form.
///
/// Values are held as typed by the user: text and number fields as [String],
/// choice fields as [String]?, boolean fields as [bool]. They are converted to
/// API types only when saving.
class DemographicsController extends SafeChangeNotifier {
  DemographicsController(this._repository);

  final DemographicsRepository _repository;

  DemographicsForm? _form;
  final Map<String, Object?> _values = {};
  final Map<String, String> _errors = {};
  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _notice;

  DemographicsForm? get form => _form;
  bool get loading => _loading;
  bool get saving => _saving;
  String? get error => _error;
  String? get notice => _notice;

  /// Field-level validation messages by field key.
  Map<String, String> get errors => Map.unmodifiable(_errors);

  Object? valueOf(String key) => _values[key];

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait<Object?>([
        _repository.fetchForm(),
        _repository.fetchAnswers(),
      ]);
      final form = results[0] as DemographicsForm?;
      final saved = results[1] as DemographicsAnswers?;
      _form = form;
      _values.clear();
      if (form != null) {
        for (final f in form.fields) {
          _values[f.key] = _initialValue(f, saved?.answers[f.key]);
        }
      }
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setValue(String key, Object? value) {
    _values[key] = value;
    _errors.remove(key);
    _notice = null;
    notifyListeners();
  }

  /// Validates required fields and number formats, then saves.
  /// Returns false (without calling the server) when validation fails.
  Future<bool> submit() async {
    final form = _form;
    if (form == null || _saving) return false;

    _errors.clear();
    final payload = <String, Object?>{};
    for (final f in form.fields) {
      final raw = _values[f.key];
      final message = _validate(f, raw);
      if (message != null) {
        _errors[f.key] = message;
        continue;
      }
      final value = _toApiValue(f, raw);
      if (value != null) payload[f.key] = value;
    }
    if (_errors.isNotEmpty) {
      _notice = null;
      _error = 'Please fix the highlighted fields.';
      notifyListeners();
      return false;
    }

    _saving = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      await _repository.save(payload);
      _notice = 'Your answers have been saved.';
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

  static Object? _initialValue(DemographicsField f, Object? saved) {
    switch (f.type) {
      case DemographicsFieldType.boolean:
        return saved == true;
      case DemographicsFieldType.choice:
        return saved is String && f.options.contains(saved) ? saved : null;
      case DemographicsFieldType.number:
        if (saved is num) {
          return saved == saved.roundToDouble()
              ? saved.toInt().toString()
              : saved.toString();
        }
        return '';
      case DemographicsFieldType.text:
        return saved?.toString() ?? '';
    }
  }

  static String? _validate(DemographicsField f, Object? raw) {
    switch (f.type) {
      case DemographicsFieldType.boolean:
        return null;
      case DemographicsFieldType.choice:
        final empty = raw == null || (raw is String && raw.isEmpty);
        return f.required && empty ? 'Choose an option.' : null;
      case DemographicsFieldType.number:
        final text = (raw as String? ?? '').trim();
        if (text.isEmpty) return f.required ? 'This field is required.' : null;
        return num.tryParse(text) == null ? 'Enter a number.' : null;
      case DemographicsFieldType.text:
        final text = (raw as String? ?? '').trim();
        return text.isEmpty && f.required ? 'This field is required.' : null;
    }
  }

  static Object? _toApiValue(DemographicsField f, Object? raw) {
    switch (f.type) {
      case DemographicsFieldType.boolean:
        return raw == true;
      case DemographicsFieldType.choice:
        return (raw is String && raw.isNotEmpty) ? raw : null;
      case DemographicsFieldType.number:
        final text = (raw as String? ?? '').trim();
        return text.isEmpty ? null : num.parse(text);
      case DemographicsFieldType.text:
        final text = (raw as String? ?? '').trim();
        return text.isEmpty ? null : text;
    }
  }
}
