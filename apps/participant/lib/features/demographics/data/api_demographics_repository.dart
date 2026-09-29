import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/demographics_repository.dart';

class ApiDemographicsRepository implements DemographicsRepository {
  ApiDemographicsRepository(this._api);

  final ApiClient _api;

  @override
  Future<DemographicsForm?> fetchForm() async {
    final json = await _api.getObjectOrNull('/me/demographics-form');
    return json == null ? null : DemographicsForm.fromJson(json);
  }

  @override
  Future<DemographicsAnswers?> fetchAnswers() async {
    final json = await _api.getObjectOrNull('/me/demographics');
    return json == null ? null : DemographicsAnswers.fromJson(json);
  }

  @override
  Future<DemographicsAnswers> save(Map<String, Object?> answers) async =>
      DemographicsAnswers.fromJson(
        await _api.putObject('/me/demographics', {'answers': answers}),
      );
}
