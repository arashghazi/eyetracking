import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/ai_repository.dart';

class ApiAiRepository implements AiRepository {
  ApiAiRepository(this._api);

  final ApiClient _api;

  String _base(int studyId) => '/studies/$studyId/ai';

  List<AiJob> _jobList(Object? value) => [
        if (value is List)
          for (final j in value)
            if (j is Map<String, dynamic>) AiJob.fromJson(j),
      ];

  @override
  Future<AiStatus> status(int studyId) async =>
      AiStatus.fromJson(await _api.getObject('${_base(studyId)}/status'));

  @override
  Future<AiBudget> setBudget(int studyId, double costCapUnits) async =>
      AiBudget.fromJson(
        await _api.putObject(
          '${_base(studyId)}/budget',
          {'cost_cap_units': costCapUnits},
        ),
      );

  @override
  Future<AiJob> createTextJob(int studyId, TextJobRequest request) async =>
      AiJob.fromJson(
        await _api.postObject('${_base(studyId)}/text-jobs', request.toJson()),
      );

  @override
  Future<List<AiJob>> createVideoJobs(
    int studyId,
    VideoJobRequest request,
  ) async =>
      _jobList(
        await _api.post('${_base(studyId)}/video-jobs', request.toJson()),
      );

  @override
  Future<List<AiJob>> jobs(
    int studyId, {
    String? status,
    String? contentId,
  }) async {
    final query = <String, String>{
      if (status != null && status.isNotEmpty) 'status': status,
      if (contentId != null && contentId.isNotEmpty) 'content_id': contentId,
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    return _jobList(await _api.getList('${_base(studyId)}/jobs$suffix'));
  }

  String _job(int studyId, String jobId) =>
      '${_base(studyId)}/jobs/${Uri.encodeComponent(jobId)}';

  @override
  Future<AiJob> cancel(int studyId, String jobId) async => AiJob.fromJson(
        await _api.postObject('${_job(studyId, jobId)}/cancel'),
      );

  @override
  Future<AiJob> retry(int studyId, String jobId) async => AiJob.fromJson(
        await _api.postObject('${_job(studyId, jobId)}/retry'),
      );

  @override
  Future<AiRunResult> run(int studyId, {int maxJobs = 5}) async =>
      AiRunResult.fromJson(
        await _api.postObject('${_base(studyId)}/run?max_jobs=$maxJobs'),
      );
}
