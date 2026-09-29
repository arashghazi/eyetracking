import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/replay_repository.dart';

class ApiReplayRepository implements ReplayRepository {
  ApiReplayRepository(this._api);

  final ApiClient _api;

  @override
  Future<ReplayBundle> load(int studyId, String sessionId) async {
    final json = await _api.getObject(
      '/studies/$studyId/sessions/${Uri.encodeComponent(sessionId)}/replay',
    );
    // The signed links are root-relative; the browser needs the service
    // address in front because the app is served from another origin.
    final media = json['media'];
    if (media is List) {
      json['media'] = [
        for (final m in media)
          if (m is Map<String, dynamic>)
            {...m, 'url': _api.resolveUrl(m['url']?.toString() ?? '')},
      ];
    }
    return ReplayBundle.fromJson(json);
  }
}
