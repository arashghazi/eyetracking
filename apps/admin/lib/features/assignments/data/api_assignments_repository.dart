import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/assignments_repository.dart';

class ApiAssignmentsRepository implements AssignmentsRepository {
  ApiAssignmentsRepository(this._api);

  final ApiClient _api;

  String _base(int studyId, String code) =>
      '/studies/$studyId/participants/${Uri.encodeComponent(code)}/assignments';

  /// Ids are numbers on the server.
  static Object _wire(String id) => int.tryParse(id) ?? id;

  @override
  Future<List<Assignment>> list(int studyId, String code) async => [
        for (final a in await _api.getList(_base(studyId, code)))
          Assignment.fromJson(a as Map<String, dynamic>),
      ];

  @override
  Future<Assignment> create(
    int studyId,
    String code, {
    required String protocolId,
    int? orderIndex,
  }) async =>
      Assignment.fromJson(
        await _api.postObject(_base(studyId, code), {
          'protocol_id': _wire(protocolId),
          'order_index': ?orderIndex,
        }),
      );

  @override
  Future<Assignment> attachContent(
    int studyId,
    String code,
    String assignmentId,
    String contentId,
  ) async =>
      Assignment.fromJson(
        await _api.putObject(
          '${_base(studyId, code)}/${Uri.encodeComponent(assignmentId)}',
          {'content_id': _wire(contentId)},
        ),
      );

  @override
  Future<Assignment> cancel(
    int studyId,
    String code,
    String assignmentId,
  ) async =>
      Assignment.fromJson(
        await _api.putObject(
          '${_base(studyId, code)}/${Uri.encodeComponent(assignmentId)}',
          {'status': 'cancelled'},
        ),
      );
}
