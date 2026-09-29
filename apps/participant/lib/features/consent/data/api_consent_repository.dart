import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/consent_repository.dart';

class ApiConsentRepository implements ConsentRepository {
  ApiConsentRepository(this._api);

  final ApiClient _api;

  @override
  Future<InformationSheet?> fetchSheet() async {
    final json = await _api.getObjectOrNull('/me/information-sheet');
    return json == null ? null : InformationSheet.fromJson(json);
  }

  @override
  Future<Consent?> fetchConsent() async {
    final json = await _api.getObject('/me/participant');
    return Consent.maybeFromJson(json['consent']);
  }

  @override
  Future<Consent> give({
    required int sheetVersion,
    required bool participate,
    required bool audioRecording,
    required bool videoRecording,
  }) async =>
      Consent.fromJson(await _api.postObject('/me/consent', {
        'sheet_version': sheetVersion,
        'participate': participate,
        'audio_recording': audioRecording,
        'video_recording': videoRecording,
      }));

  @override
  Future<Consent> withdraw() async =>
      Consent.fromJson(await _api.postObject('/me/consent/withdraw'));
}
