import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';

import '../../content/domain/media_picker.dart';
import '../../sessions/domain/sessions_repository.dart';
import '../domain/pilot_repository.dart';
import 'number_input.dart';

/// The file a researcher picked for an import.
class PickedExport {
  const PickedExport({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// The Tracker comparison section: pick a session, import an export of a
/// research eye tracker for it, and compare the two on that session.
///
/// Researchers import; analysts can list and compare (the server refuses an
/// import from anyone else, and the form is hidden for them).
class TrackerComparisonController extends SafeChangeNotifier {
  TrackerComparisonController(
    this._pilot,
    this._sessions,
    this._picker,
    this.studyId, {
    required this.canImport,
  });

  /// What the file dialog offers.
  static const acceptedFiles = '.csv,.tsv,.txt';
  static const maxFileBytes = 150 * 1024 * 1024;
  static const defaultTolerance = 40;

  /// The delimiter choices; an empty value lets the server guess.
  static const delimiters = <(String, String)>[
    ('', 'Auto'),
    (',', 'Comma'),
    (';', 'Semicolon'),
    ('\t', 'Tab'),
  ];

  final PilotRepository _pilot;
  final SessionsRepository _sessions;
  final MediaPicker _picker;
  final int studyId;
  final bool canImport;

  // ------------------------------------------------------------- sessions
  List<SessionListItem> _sessionList = const [];
  bool _sessionsLoading = false;
  bool _sessionsLoaded = false;
  String? _sessionsError;
  String? _selectedId;

  // ----------------------------------------------------------- recordings
  List<ReferenceRecording> _recordings = const [];
  bool _recordingsLoading = false;
  String? _recordingsError;

  // ---------------------------------------------------------- import form
  PickedExport? _file;
  final Map<String, String> _values = {
    'source': '',
    'time_column': '',
    'x_column': '',
    'y_column': '',
    'valid_column': '',
    'valid_values': '',
    'offset': '0',
    'origin_x': '0',
    'origin_y': '0',
    'auto_align_window_ms': '0',
  };
  String _timeUnit = ReferenceTimeUnit.ms;
  String _coordSpace = ReferenceCoordSpace.cssPx;
  String _delimiter = '';
  Map<String, String> _errors = const {};
  bool _importing = false;
  String? _importError;
  String? _notice;

  // ------------------------------------------------------------- compare
  String _tolerance = '$defaultTolerance';
  String? _toleranceError;
  String? _comparingId;
  String? _comparedId;
  ReferenceComparison? _comparison;
  String? _compareError;

  List<SessionListItem> get sessions => _sessionList;
  bool get sessionsLoading => _sessionsLoading;
  bool get sessionsLoaded => _sessionsLoaded;
  String? get sessionsError => _sessionsError;
  String? get selectedId => _selectedId;
  SessionListItem? get selectedSession {
    for (final s in _sessionList) {
      if (s.id == _selectedId) return s;
    }
    return null;
  }

  List<ReferenceRecording> get recordings => _recordings;
  bool get recordingsLoading => _recordingsLoading;
  String? get recordingsError => _recordingsError;

  PickedExport? get file => _file;
  String value(String key) => _values[key] ?? '';
  String get timeUnit => _timeUnit;
  String get coordSpace => _coordSpace;
  String get delimiter => _delimiter;
  String? errorFor(String key) => _errors[key];
  bool get importing => _importing;

  /// The server's refusal of the last import, exactly as written.
  String? get importError => _importError;
  String? get notice => _notice;

  String get tolerance => _tolerance;
  String? get toleranceError => _toleranceError;
  String? get comparingId => _comparingId;

  /// The recording the shown [comparison] belongs to.
  String? get comparedId => _comparedId;
  ReferenceComparison? get comparison => _comparison;
  String? get compareError => _compareError;

  // ------------------------------------------------------------- sessions

  Future<void> loadSessions() async {
    if (_sessionsLoading) return;
    _sessionsLoading = true;
    _sessionsError = null;
    notifyListeners();
    try {
      _sessionList = await _sessions.list(studyId);
      _sessionsLoaded = true;
    } catch (e) {
      _sessionsError = userMessage(e);
    } finally {
      _sessionsLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectSession(String? sessionId) async {
    if (sessionId == _selectedId) return;
    _selectedId = sessionId;
    _recordings = const [];
    _recordingsError = null;
    _comparison = null;
    _comparedId = null;
    _compareError = null;
    _importError = null;
    _notice = null;
    notifyListeners();
    if (sessionId != null) await loadRecordings();
  }

  Future<void> loadRecordings() async {
    final id = _selectedId;
    if (id == null) return;
    _recordingsLoading = true;
    _recordingsError = null;
    notifyListeners();
    try {
      final list = await _pilot.references(studyId, id);
      if (id == _selectedId) _recordings = list;
    } catch (e) {
      if (id == _selectedId) _recordingsError = userMessage(e);
    } finally {
      _recordingsLoading = false;
      notifyListeners();
    }
  }

  // --------------------------------------------------------------- import

  void setValue(String key, String value) {
    _values[key] = value;
    if (_errors.containsKey(key)) _errors = {..._errors}..remove(key);
    notifyListeners();
  }

  void setTimeUnit(String value) {
    _timeUnit = value;
    notifyListeners();
  }

  void setCoordSpace(String value) {
    _coordSpace = value;
    notifyListeners();
  }

  void setDelimiter(String value) {
    _delimiter = value;
    notifyListeners();
  }

  /// Opens the file dialog for a tracker export.
  Future<void> pickFile() async {
    final picked = await _picker.pick(accept: acceptedFiles);
    if (picked == null) return;
    _file = PickedExport(name: picked.name, bytes: picked.bytes);
    if (_errors.containsKey('file')) _errors = {..._errors}..remove('file');
    notifyListeners();
  }

  void clearFile() {
    _file = null;
    notifyListeners();
  }

  /// Builds the request when every field is acceptable; otherwise sets the
  /// field errors and returns null. The server has the last word on the
  /// columns (a missing column is a 422 that names the file's columns).
  ReferenceImportRequest? _validate() {
    final errors = <String, String>{};
    final file = _file;
    if (file == null) {
      errors['file'] = 'Choose the tracker export first.';
    } else if (file.bytes.isEmpty) {
      errors['file'] = 'The file is empty.';
    } else if (file.bytes.length > maxFileBytes) {
      errors['file'] = 'The file is larger than 150 MB.';
    }
    final source = value('source').trim();
    if (source.isEmpty) {
      errors['source'] = "Enter the tracker's name and model.";
    } else if (source.length > ReferenceImportRequest.maxSourceChars) {
      errors['source'] =
          'At most ${ReferenceImportRequest.maxSourceChars} characters.';
    }
    for (final key in const ['time_column', 'x_column', 'y_column']) {
      if (value(key).trim().isEmpty) errors[key] = 'Enter the column name.';
    }
    double number(String key) {
      final v = parseDecimal(value(key));
      if (v == null) errors[key] = 'Enter a number.';
      return v ?? 0;
    }

    final offset = number('offset');
    final originX = number('origin_x');
    final originY = number('origin_y');
    var align = 0;
    final alignText = value('auto_align_window_ms').trim();
    if (alignText.isNotEmpty) {
      final v = parseWhole(alignText);
      if (v == null || v < 0 || v > ReferenceImportRequest.maxAutoAlignWindowMs) {
        errors['auto_align_window_ms'] =
            'Enter a whole number from 0 to ${ReferenceImportRequest.maxAutoAlignWindowMs}.';
      } else {
        align = v;
      }
    }
    _errors = errors;
    if (errors.isNotEmpty) return null;
    return ReferenceImportRequest(
      source: source,
      timeColumn: value('time_column'),
      xColumn: value('x_column'),
      yColumn: value('y_column'),
      validColumn: value('valid_column'),
      validValues: value('valid_values'),
      timeUnit: _timeUnit,
      offset: offset,
      coordSpace: _coordSpace,
      originX: originX,
      originY: originY,
      delimiter: _delimiter,
      autoAlignWindowMs: align,
    );
  }

  /// Uploads the export for the selected session. Returns whether the
  /// server took it; a refusal is kept in [importError] as written.
  Future<bool> importFile() async {
    final id = _selectedId;
    if (!canImport || _importing || id == null) return false;
    _importError = null;
    _notice = null;
    final request = _validate();
    if (request == null) {
      notifyListeners();
      return false;
    }
    final file = _file!;
    _importing = true;
    notifyListeners();
    try {
      final recording = await _pilot.importReference(
        studyId,
        id,
        bytes: file.bytes,
        filename: file.name,
        request: request,
      );
      _notice = 'Imported ${recording.sampleCount} samples '
          '(${recording.validCount} valid) from ${recording.source}.';
      _file = null;
      _importing = false;
      await loadRecordings();
      return true;
    } catch (e) {
      _importError = userMessage(e);
      return false;
    } finally {
      _importing = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------- compare

  void setTolerance(String value) {
    _tolerance = value;
    _toleranceError = null;
    notifyListeners();
  }

  /// Compares the webcam estimate with [recording] within the tolerance.
  Future<void> compare(ReferenceRecording recording) async {
    final id = _selectedId;
    if (id == null || _comparingId != null) return;
    final tolerance = parseWhole(_tolerance);
    if (tolerance == null || tolerance < 1 || tolerance > 500) {
      _toleranceError = 'Enter a whole number of ms from 1 to 500.';
      notifyListeners();
      return;
    }
    _comparingId = recording.id;
    _compareError = null;
    notifyListeners();
    try {
      final result = await _pilot.compare(
        studyId,
        id,
        recording.id,
        toleranceMs: tolerance,
      );
      if (id == _selectedId) {
        _comparison = result;
        _comparedId = recording.id;
      }
    } catch (e) {
      _compareError = userMessage(e);
    } finally {
      _comparingId = null;
      notifyListeners();
    }
  }

  void dismissImportError() {
    _importError = null;
    notifyListeners();
  }

  void dismissNotice() {
    _notice = null;
    notifyListeners();
  }
}
