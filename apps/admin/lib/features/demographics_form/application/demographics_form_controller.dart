import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/demographics_form_repository.dart';

/// One editable row of the form editor.
class FieldDraft {
  FieldDraft({
    required this.id,
    this.key = '',
    this.label = '',
    this.type = DemographicsFieldType.text,
    this.optionsText = '',
    this.required = false,
  });

  /// Stable identity of the row, so widgets keep their state when rows move.
  final int id;
  String key;
  String label;
  DemographicsFieldType type;

  /// Options as typed, separated by commas (choice fields only).
  String optionsText;
  bool required;

  List<String> get options => [
        for (final o in optionsText.split(','))
          if (o.trim().isNotEmpty) o.trim(),
      ];

  DemographicsField toField() => DemographicsField(
        key: key.trim(),
        label: label.trim().isEmpty ? key.trim() : label.trim(),
        type: type,
        options: type == DemographicsFieldType.choice ? options : const [],
        required: required,
      );
}

class DemographicsFormController extends SafeChangeNotifier {
  DemographicsFormController(this._repository, this.studyId);

  final DemographicsFormRepository _repository;
  final int studyId;

  DemographicsForm? _current;
  final List<FieldDraft> _rows = [];
  final Map<int, String> _rowErrors = {};
  int _nextId = 1;
  bool _loading = false;
  bool _loaded = false;
  bool _publishing = false;
  String? _error;
  String? _notice;

  DemographicsForm? get current => _current;
  List<FieldDraft> get rows => List.unmodifiable(_rows);
  bool get loading => _loading;
  bool get loaded => _loaded;
  bool get publishing => _publishing;
  String? get error => _error;
  String? get notice => _notice;

  /// Validation message per row id, filled by [publish].
  String? errorFor(FieldDraft row) => _rowErrors[row.id];

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _current = await _repository.current(studyId);
      _rows
        ..clear()
        ..addAll([
          for (final f in _current?.fields ?? const <DemographicsField>[])
            FieldDraft(
              id: _nextId++,
              key: f.key,
              label: f.label,
              type: f.type,
              optionsText: f.options.join(', '),
              required: f.required,
            ),
        ]);
      _rowErrors.clear();
      _loaded = true;
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void addRow() {
    _rows.add(FieldDraft(id: _nextId++));
    _notice = null;
    notifyListeners();
  }

  void removeRow(FieldDraft row) {
    _rows.remove(row);
    _rowErrors.remove(row.id);
    _notice = null;
    notifyListeners();
  }

  void moveRow(FieldDraft row, int delta) {
    final from = _rows.indexOf(row);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= _rows.length) return;
    _rows
      ..removeAt(from)
      ..insert(to, row);
    notifyListeners();
  }

  /// Applies an edit to [row]. Text edits do not rebuild the editor.
  void update(
    FieldDraft row, {
    String? key,
    String? label,
    DemographicsFieldType? type,
    String? optionsText,
    bool? required,
    bool rebuild = false,
  }) {
    if (key != null) row.key = key;
    if (label != null) row.label = label;
    if (type != null) row.type = type;
    if (optionsText != null) row.optionsText = optionsText;
    if (required != null) row.required = required;
    _rowErrors.remove(row.id);
    _notice = null;
    if (rebuild || type != null || required != null) notifyListeners();
  }

  /// Checks the rows the same way the server does.
  bool validate() {
    _rowErrors.clear();
    final seen = <String>{};
    for (final row in _rows) {
      final key = row.key.trim();
      if (key.isEmpty) {
        _rowErrors[row.id] = 'Every field needs a key.';
      } else if (!seen.add(key)) {
        _rowErrors[row.id] = 'Key "$key" is used more than once.';
      } else if (row.type == DemographicsFieldType.choice &&
          row.options.isEmpty) {
        _rowErrors[row.id] = 'A choice field needs at least one option.';
      }
    }
    return _rowErrors.isEmpty;
  }

  Future<bool> publish() async {
    if (_publishing) return false;
    if (!validate()) {
      _error = 'Please fix the highlighted fields before publishing.';
      _notice = null;
      notifyListeners();
      return false;
    }
    _publishing = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      _current = await _repository.publish(
        studyId,
        [for (final r in _rows) r.toField()],
      );
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
