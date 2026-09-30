import 'package:eyetracking_core/eyetracking_core.dart';

abstract class MeasurementSettingsRepository {
  /// The settings, with their version.
  Future<MeasurementSettings> load(int studyId);

  /// Researchers only; analysts get a 403. A real change creates the next
  /// settings version and stores who changed it and why ([rationale], at most
  /// 1000 characters, optional); the same values again create nothing.
  Future<MeasurementSettings> save(
    int studyId,
    MeasurementSettings settings, {
    String? rationale,
  });

  /// Saves only the named fields (wire names), for example the changes of a
  /// threshold review. The other settings keep their values.
  Future<MeasurementSettings> saveChanges(
    int studyId,
    Map<String, dynamic> changes, {
    String? rationale,
  });
}
