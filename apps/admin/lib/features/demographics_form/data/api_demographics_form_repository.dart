import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/demographics_form_repository.dart';

class ApiDemographicsFormRepository implements DemographicsFormRepository {
  ApiDemographicsFormRepository(this._api);

  final ApiClient _api;

  @override
  Future<DemographicsForm?> current(int studyId) async {
    final json = await _api.getObjectOrNull('/studies/$studyId/demographics-form');
    return json == null ? null : DemographicsForm.fromJson(json);
  }

  @override
  Future<DemographicsForm> publish(
    int studyId,
    List<DemographicsField> fields,
  ) async =>
      DemographicsForm.fromJson(
        await _api.putObject('/studies/$studyId/demographics-form', {
          'fields': [for (final f in fields) f.toJson()],
        }),
      );
}
