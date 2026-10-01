import 'package:eyetracking_core/eyetracking_core.dart';

import '../../exports/application/download_controller.dart';
import '../../live/domain/live_models.dart';
import '../domain/pilot_readings.dart';
import '../domain/pilot_repository.dart';

/// The Report section: the pilot summary of the study and its CSV. Synthetic
/// sessions are left out unless included on purpose.
class PilotReportController extends SafeChangeNotifier {
  PilotReportController(this._repository, this.studyId, this.downloads);

  final PilotRepository _repository;
  final int studyId;

  /// Hands the CSV to the browser.
  final DownloadController downloads;

  PilotReportData? _data;
  bool _includeSynthetic = false;
  bool _loading = false;
  String? _error;

  PilotReport? get report => _data?.report;

  /// The conversation columns of one report row.
  ConversationReportColumns conversationColumns(String sessionId) =>
      _data?.columnsFor(sessionId) ?? const ConversationReportColumns();
  bool get includeSynthetic => _includeSynthetic;
  bool get loading => _loading;
  String? get error => _error;

  /// The file name the CSV is saved under.
  String get csvFilename => 'pilot_sessions_study$studyId.csv';

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    final wanted = _includeSynthetic;
    try {
      final data = await _repository.report(studyId, includeSynthetic: wanted);
      // A switch flipped while this ran has started its own read.
      if (wanted == _includeSynthetic) _data = data;
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setIncludeSynthetic(bool value) {
    _includeSynthetic = value;
    _loading = false;
    return load();
  }

  Future<bool> downloadCsv() => downloads.download(
        () => _repository.reportCsv(studyId, includeSynthetic: _includeSynthetic),
        filename: csvFilename,
        mimeType: DownloadTypes.csv,
      );

  void dismissError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    downloads.dispose();
    super.dispose();
  }
}
