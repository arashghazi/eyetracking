import 'package:eyetracking_core/eyetracking_core.dart';

abstract class ConsentRepository {
  /// The current information sheet, or null when none is published.
  Future<InformationSheet?> fetchSheet();

  /// The participant's latest consent record, or null if they never answered.
  Future<Consent?> fetchConsent();

  Future<Consent> give({
    required int sheetVersion,
    required bool participate,
    required bool audioRecording,
    required bool videoRecording,
  });

  Future<Consent> withdraw();
}
