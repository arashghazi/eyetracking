import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/live_repository.dart';

class ApiLiveRepository implements LiveRepository {
  ApiLiveRepository(this._api);

  final ApiClient _api;

  String _base(String id) => '/me/sessions/${Uri.encodeComponent(id)}/live';

  @override
  Future<LiveSnapshot> snapshot(String sessionId) async =>
      LiveSnapshot.fromJson(await _api.getObject(_base(sessionId)));

  @override
  Future<LiveStart> start(
    String sessionId, {
    required LiveInputMode mode,
    required bool allowTranscript,
    int? tMs,
  }) async {
    final start = LiveStart.fromJson(
      await _api.postObject('${_base(sessionId)}/start', {
        'input_mode': mode.wire,
        'allow_transcript': allowTranscript,
        't_ms': ?tMs,
      }),
    );
    // The sample video is a path on the service (`/static/live/...`); the
    // app is served from another origin, so it gets the service address.
    final url = start.avatar.videoUrl;
    if (url == null) return start;
    return LiveStart(
      conversation: start.conversation,
      turns: start.turns,
      avatar: start.avatar.copyWith(videoUrl: _api.resolveUrl(url)),
      faceLayout: start.faceLayout,
      limits: start.limits,
      resumed: start.resumed,
    );
  }

  @override
  Future<LiveTurnResult> sendTurn(
    String sessionId, {
    required int expectTurn,
    required String text,
    int? tMs,
  }) async =>
      LiveTurnResult.fromJson(
        await _api.postObject('${_base(sessionId)}/turn', {
          'expect_turn': expectTurn,
          'text': text,
          't_ms': ?tMs,
        }),
      );

  @override
  Future<LiveTurnResult> sendAudio(
    String sessionId, {
    required int expectTurn,
    required AudioClip clip,
    int? tMs,
  }) async =>
      LiveTurnResult.fromJson(
        await _api.uploadFile(
          '${_base(sessionId)}/turn-audio',
          bytes: clip.bytes,
          filename: clip.filename,
          contentType: clip.mediaType,
          fields: {
            'expect_turn': '$expectTurn',
            if (tMs != null) 't_ms': '$tMs',
          },
        ),
      );

  @override
  Future<LiveEndResult> end(String sessionId, {int? tMs}) async =>
      LiveEndResult.fromJson(
        await _api.postObject('${_base(sessionId)}/end', {'t_ms': ?tMs}),
      );
}
