import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/protocols_repository.dart';

class ApiProtocolsRepository implements ProtocolsRepository {
  ApiProtocolsRepository(this._api);

  final ApiClient _api;

  String _base(int studyId) => '/studies/$studyId/protocols';
  String _one(int studyId, String id) =>
      '${_base(studyId)}/${Uri.encodeComponent(id)}';

  @override
  Future<List<ProtocolSummary>> list(int studyId) async => [
        for (final p in await _api.getList(_base(studyId)))
          ProtocolSummary.fromJson(p as Map<String, dynamic>),
      ];

  @override
  Future<ProtocolDetail> get(int studyId, String protocolId) async =>
      ProtocolDetail.fromJson(await _api.getObject(_one(studyId, protocolId)));

  /// The answer of a write carries the definition; when it does not, the
  /// definition is read again rather than guessed.
  Future<ProtocolDetail> _detail(
    int studyId,
    Map<String, dynamic> json,
  ) async =>
      json['definition'] is Map<String, dynamic>
          ? ProtocolDetail.fromJson(json)
          : get(studyId, json['id']?.toString() ?? '');

  @override
  Future<ProtocolDetail> create(
    int studyId,
    String name,
    ProtocolDefinition definition,
  ) async =>
      _detail(
        studyId,
        await _api.postObject(_base(studyId), {
          'name': name,
          'definition': definition.toJson(),
        }),
      );

  @override
  Future<ProtocolDetail> update(
    int studyId,
    String protocolId, {
    String? name,
    ProtocolDefinition? definition,
  }) async =>
      _detail(
        studyId,
        await _api.putObject(_one(studyId, protocolId), {
          'name': ?name,
          if (definition != null) 'definition': definition.toJson(),
        }),
      );

  @override
  Future<ProtocolDetail> publish(int studyId, String protocolId) async =>
      _detail(
        studyId,
        await _api.postObject('${_one(studyId, protocolId)}/publish'),
      );

  @override
  Future<ProtocolDetail> newDraft(int studyId, String protocolId) async =>
      _detail(
        studyId,
        await _api.postObject('${_one(studyId, protocolId)}/new-draft'),
      );
}
