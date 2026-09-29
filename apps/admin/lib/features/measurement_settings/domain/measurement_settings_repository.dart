import 'package:eyetracking_core/eyetracking_core.dart';

abstract class MeasurementSettingsRepository {
  Future<MeasurementSettings> load(int studyId);

  /// Researchers only; analysts get a 403.
  Future<MeasurementSettings> save(int studyId, MeasurementSettings settings);
}
