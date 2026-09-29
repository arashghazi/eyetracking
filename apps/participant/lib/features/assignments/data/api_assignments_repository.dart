import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/assignments_repository.dart';

class ApiAssignmentsRepository implements AssignmentsRepository {
  ApiAssignmentsRepository(this._api);

  final ApiClient _api;

  String _base(String id) => '/me/assignments/${Uri.encodeComponent(id)}';

  @override
  Future<List<Assignment>> list() async => [
        for (final a in await _api.getList('/me/assignments'))
          Assignment.fromJson(a as Map<String, dynamic>),
      ];

  @override
  Future<Assignment> submitTopic(
    String assignmentId, {
    required String topic,
    String? freeText,
  }) async =>
      Assignment.fromJson(
        await _api.postObject('${_base(assignmentId)}/topic', {
          'topic': topic,
          if (freeText != null && freeText.trim().isNotEmpty)
            'free_text': freeText.trim(),
        }),
      );

  @override
  Future<PersonalizedContent> content(String assignmentId) async {
    final json = await _api.getObject('${_base(assignmentId)}/content');
    // The server sends signed paths such as /media/<token>; the video is
    // played from another origin than the app, so they need the service
    // address in front. The signature itself is never touched.
    return PersonalizedContent.fromJson({
      ...json,
      'segments': [
        for (final s in (json['segments'] as List<dynamic>? ?? const []))
          if (s is Map<String, dynamic>)
            {
              ...s,
              if (s['media_url'] is String)
                'media_url': _api.resolveUrl(s['media_url'] as String),
            },
      ],
    });
  }
}
