import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/measurement_settings_repository.dart';

class ApiMeasurementSettingsRepository implements MeasurementSettingsRepository {
  ApiMeasurementSettingsRepository(this._api);

  final ApiClient _api;

  @override
  Future<MeasurementSettings> load(int studyId) async =>
      MeasurementSettings.fromJson(
        await _api.getObject('/studies/$studyId/measurement-settings'),
      );

  @override
  Future<MeasurementSettings> save(
    int studyId,
    MeasurementSettings settings, {
    String? rationale,
  }) =>
      saveChanges(studyId, settings.toJson(), rationale: rationale);

  @override
  Future<MeasurementSettings> saveChanges(
    int studyId,
    Map<String, dynamic> changes, {
    String? rationale,
  }) async {
    final why = rationale?.trim();
    return MeasurementSettings.fromJson(
      await _api.putObject('/studies/$studyId/measurement-settings', {
        ...changes,
        if (why != null && why.isNotEmpty) 'rationale': why,
      }),
    );
  }
}
