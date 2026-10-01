import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';

import 'pilot_readings.dart';

/// The step 6 endpoints (supervised pilot). Study data needs membership:
/// researchers write and monitor, researchers and analysts read. An
/// administrator who is not a member gets a 403 whose message is shown as the
/// server wrote it.
abstract class PilotRepository {
  // ------------------------------------------------------- settings history

  /// Every settings version, newest first. Before any change it holds one
  /// synthesized entry without a date.
  Future<List<SettingsVersion>> settingsHistory(int studyId);

  // ------------------------------------------------------ threshold review

  /// What candidate thresholds would change on the recorded sessions.
  /// Saves nothing. An unknown field or an out-of-range value is a 422.
  Future<ThresholdReview> thresholdReview(
    int studyId, {
    Map<String, dynamic> changes = const {},
    bool includeSynthetic = false,
  });

  // ---------------------------------------------------------- observations

  /// Oldest first (researchers and analysts).
  Future<List<Observation>> observations(int studyId, String sessionId);

  /// Researchers only. Observations cannot be edited or deleted.
  Future<Observation> addObservation(
    int studyId,
    String sessionId,
    ObservationRequest request,
  );

  // ---------------------------------------------------------- live monitor

  /// Sessions not ended and started within the last 12 hours, newest first.
  Future<List<ActiveSession>> activeSessions(int studyId);

  /// One poll of the live monitor. [first] is true on the first call after
  /// monitoring starts: that call is written to the access log.
  Future<LiveReading> live(int studyId, String sessionId, {bool first = false});

  // --------------------------------------------------------------- debrief

  Future<DebriefForm> debriefForm(int studyId);

  /// Researchers only. Changed [questions] make a new version; [enabled]
  /// alone switches the current version on or off.
  Future<DebriefForm> saveDebriefForm(
    int studyId, {
    List<DebriefQuestion>? questions,
    bool? enabled,
  });

  // ------------------------------------------------- research eye tracker

  /// Uploads a tracker export for a session (researchers only). A file the
  /// server cannot read is a 422 that names the file's columns.
  Future<ReferenceRecording> importReference(
    int studyId,
    String sessionId, {
    required Uint8List bytes,
    required String filename,
    required ReferenceImportRequest request,
  });

  Future<List<ReferenceRecording>> references(int studyId, String sessionId);

  Future<ReferenceComparison> compare(
    int studyId,
    String sessionId,
    String recordingId, {
    int toleranceMs = 40,
  });

  // ---------------------------------------------------------------- report

  Future<PilotReportData> report(int studyId, {bool includeSynthetic = false});

  /// The report rows as UTF-8 CSV with a byte order mark.
  Future<Uint8List> reportCsv(int studyId, {bool includeSynthetic = false});
}
