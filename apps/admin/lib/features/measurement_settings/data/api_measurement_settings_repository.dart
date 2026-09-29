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
    MeasurementSettings settings,
  ) async =>
      MeasurementSettings.fromJson(
        await _api.putObject(
          '/studies/$studyId/measurement-settings',
          settings.toJson(),
        ),
      );
}
