import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/content_repository.dart';

class ApiContentRepository implements ContentRepository {
  ApiContentRepository(this._api);

  final ApiClient _api;

  String _base(int studyId) => '/studies/$studyId/content';
  String _one(int studyId, String id) =>
      '${_base(studyId)}/${Uri.encodeComponent(id)}';

  Map<String, dynamic> _body({
    required String title,
    required List<String> topicTags,
    required String faceId,
    required String voiceId,
    required ContentDefinition definition,
  }) =>
      {
        'title': title,
        'topic_tags': topicTags,
        'face_id': faceId,
        'voice_id': voiceId,
        'definition': definition.toJson(),
      };

  Future<ContentDetail> _detail(int studyId, Map<String, dynamic> json) async =>
      json['definition'] is Map<String, dynamic>
          ? ContentDetail.fromJson(json)
          : get(studyId, json['id']?.toString() ?? '');

  @override
  Future<List<ContentSummary>> list(int studyId) async => [
        for (final c in await _api.getList(_base(studyId)))
          ContentSummary.fromJson(c as Map<String, dynamic>),
      ];

  @override
  Future<ContentDetail> get(int studyId, String contentId) async =>
      ContentDetail.fromJson(await _api.getObject(_one(studyId, contentId)));

  @override
  Future<ContentDetail> create(
    int studyId, {
    required String title,
    required List<String> topicTags,
    required String faceId,
    required String voiceId,
    required ContentDefinition definition,
  }) async =>
      _detail(
        studyId,
        await _api.postObject(
          _base(studyId),
          _body(
            title: title,
            topicTags: topicTags,
            faceId: faceId,
            voiceId: voiceId,
            definition: definition,
          ),
        ),
      );

  @override
  Future<ContentDetail> update(
    int studyId,
    String contentId, {
    required String title,
    required List<String> topicTags,
    required String faceId,
    required String voiceId,
    required ContentDefinition definition,
  }) async =>
      _detail(
        studyId,
        await _api.putObject(
          _one(studyId, contentId),
          _body(
            title: title,
            topicTags: topicTags,
            faceId: faceId,
            voiceId: voiceId,
            definition: definition,
          ),
        ),
      );

  @override
  Future<ContentDetail> approve(int studyId, String contentId) async =>
      _detail(
        studyId,
        await _api.postObject('${_one(studyId, contentId)}/approve'),
      );

  @override
  Future<MediaInfo> uploadMedia(
    int studyId,
    String contentId,
    String key, {
    required Uint8List bytes,
    required String filename,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async =>
      MediaInfo.fromJson(
        await _api.uploadFile(
          '${_one(studyId, contentId)}/media/${Uri.encodeComponent(key)}',
          bytes: bytes,
          filename: filename,
          contentType: contentType,
          onProgress: onProgress,
        ),
      );

  @override
  Future<List<MediaInfo>> media(int studyId, String contentId) async => [
        for (final m in await _api.getList('${_one(studyId, contentId)}/media'))
          MediaInfo.fromJson(m as Map<String, dynamic>),
      ];
}
