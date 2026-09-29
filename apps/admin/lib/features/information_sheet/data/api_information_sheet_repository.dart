import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/information_sheet_repository.dart';

class ApiInformationSheetRepository implements InformationSheetRepository {
  ApiInformationSheetRepository(this._api);

  final ApiClient _api;

  @override
  Future<InformationSheet?> current(int studyId) async {
    final json = await _api.getObjectOrNull('/studies/$studyId/information-sheet');
    return json == null ? null : InformationSheet.fromJson(json);
  }

  @override
  Future<InformationSheet> publish(int studyId, SheetContent content) async =>
      InformationSheet.fromJson(
        await _api.putObject('/studies/$studyId/information-sheet', content.toJson()),
      );
}
