import 'package:eyetracking_core/eyetracking_core.dart';

import '../../exports/application/download_controller.dart';
import '../../exports/domain/exports_repository.dart';
import '../domain/analysis_filters.dart';
import '../domain/analysis_repository.dart';

/// The Analysis tab: filters, the result of the query and the exports that
/// use the same filters.
class AnalysisController extends SafeChangeNotifier {
  AnalysisController(
    this._repository,
    this._exports,
    this.studyId,
    FileSaver save,
  ) : downloads = DownloadController(save) {
    downloads.addListener(notifyListeners);
  }

  /// Rows drawn in the table; the rest is in the export.
  static const displayLimit = 500;

  final AnalysisRepository _repository;
  final ExportsRepository _exports;
  final int studyId;

  /// Runs the export buttons.
  final DownloadController downloads;

  AnalysisFilters _filters = const AnalysisFilters();
  AnalysisResponse? _response;
  AnalysisFilters? _appliedFilters;
  bool _loading = false;
  String? _error;

  List<DictionaryEntry>? _dictionary;
  bool _dictionaryLoading = false;

  /// The filters as edited (applied only by [apply]).
  AnalysisFilters get filters => _filters;

  /// What the current result was computed with.
  AnalysisFilters? get appliedFilters => _appliedFilters;
  AnalysisResponse? get response => _response;
  bool get loading => _loading;
  String? get error => _error ?? downloads.error;
  String? get notice => downloads.notice;
  bool get dictionaryLoading => _dictionaryLoading;
  List<DictionaryEntry>? get dictionary => _dictionary;

  // ------------------------------------------------------------ filters

  void setParticipant(String v) => _edit(_filters.copyWith(participant: v));
  void setPath(String? v) => _edit(_filters.copyWith(path: v));
  void setProtocolVersion(String v) =>
      _edit(_filters.copyWith(protocolVersion: v));
  void setDevice(String v) => _edit(_filters.copyWith(device: v));
  void setFrom(String v) => _edit(_filters.copyWith(from: v));
  void setTo(String v) => _edit(_filters.copyWith(to: v));
  void setIncludeSynthetic(bool v) =>
      _edit(_filters.copyWith(includeSynthetic: v));

  /// Turns a quality grade on or off. The last selected grade stays on.
  void toggleQuality(String grade, bool on) {
    if (!AnalysisFilters.selectableQualities.contains(grade)) return;
    final next = {..._filters.qualities};
    if (on) {
      next.add(grade);
    } else {
      if (next.length == 1 && next.contains(grade)) return;
      next.remove(grade);
    }
    _edit(_filters.copyWith(qualities: next));
  }

  void resetFilters() {
    _error = null;
    _edit(const AnalysisFilters());
  }

  void _edit(AnalysisFilters next) {
    _filters = next;
    notifyListeners();
  }

  // -------------------------------------------------------------- query

  /// Asks the server for the analysis with the current filters.
  Future<bool> apply() async {
    final problem = _filters.validate();
    if (problem != null) {
      _error = problem;
      notifyListeners();
      return false;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    final asked = _filters;
    try {
      _response = await _repository.analysis(studyId, asked);
      _appliedFilters = asked;
      return true;
    } catch (e) {
      _error = userMessage(e);
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ exports

  /// Rejects an export when the filters cannot be sent.
  bool _exportReady() {
    final problem = _filters.validate();
    if (problem == null) return true;
    _error = problem;
    notifyListeners();
    return false;
  }

  Future<bool> downloadSessionsCsv() async {
    if (!_exportReady()) return false;
    final f = _filters;
    return downloads.download(
      () => _exports.sessionsCsv(studyId, f),
      filename: 'sessions.csv',
      mimeType: DownloadTypes.csv,
    );
  }

  Future<bool> downloadSessionsJson() async {
    if (!_exportReady()) return false;
    final f = _filters;
    return downloads.download(
      () => _exports.sessionsJson(studyId, f),
      filename: 'sessions.json',
      mimeType: DownloadTypes.json,
    );
  }

  /// Fetches the data dictionary (once) so the dialog can list it.
  Future<List<DictionaryEntry>?> loadDictionary() async {
    if (_dictionary != null) return _dictionary;
    if (_dictionaryLoading) return null;
    _dictionaryLoading = true;
    _error = null;
    notifyListeners();
    try {
      _dictionary = await _exports.dataDictionary(studyId);
      return _dictionary;
    } catch (e) {
      _error = userMessage(e);
      return null;
    } finally {
      _dictionaryLoading = false;
      notifyListeners();
    }
  }

  void dismissError() {
    _error = null;
    downloads.dismissError();
    notifyListeners();
  }

  void dismissNotice() => downloads.dismissNotice();

  @override
  void dispose() {
    downloads.removeListener(notifyListeners);
    downloads.dispose();
    super.dispose();
  }
}
