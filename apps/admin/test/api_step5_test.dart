import 'dart:convert';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:research_admin/features/ai/data/api_ai_repository.dart';
import 'package:research_admin/features/content/data/api_content_repository.dart';

/// The wire of the step 5 endpoints against a canned HTTP client.
class Wire {
  final List<http.BaseRequest> requests = [];
  final List<String> bodies = [];
  final Map<String, (int, Object)> answers = {};

  ApiClient client() => ApiClient(
        baseUrl: 'http://api.test:8000',
        tokenStore: TokenStore()..save('tok'),
        httpClient: MockClient.streaming((request, body) async {
          requests.add(request);
          bodies.add(utf8.decode(await body.expand((c) => c).toList()));
          final key = '${request.method} ${request.url.path}';
          final answer = answers[key] ?? (404, {'detail': 'no route $key'});
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode(answer.$2))),
            answer.$1,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

  http.BaseRequest get last => requests.last;
  Object? get lastBody => bodies.last.isEmpty ? null : jsonDecode(bodies.last);
}

Map<String, dynamic> jobJson(int id, {String status = 'queued'}) => {
      'id': id,
      'kind': 'text',
      'status': status,
      'provider': 'fake',
      'content_id': 7,
      'assignment_id': null,
      'segment_id': null,
      'attempts': 0,
      'max_attempts': 3,
      'cost_estimate_units': 0.05,
      'cost_actual_units': null,
      'error': null,
      'created_at': '2026-09-29T10:00:00',
      'started_at': null,
      'finished_at': null,
      'request': {'topic': 'trains'},
      'result': {},
    };

void main() {
  test('status: providers, worker, budget and the free-text setting', () async {
    final w = Wire()
      ..answers['GET /studies/1/ai/status'] = (
        200,
        {
          'text_provider': {
            'name': 'anthropic',
            'model': 'claude-x',
            'configured': true,
            'synthetic': false,
          },
          'video_provider': {'name': 'fake', 'configured': true, 'synthetic': true},
          'budget': {
            'cost_cap_units': 10,
            'spent_units': 2.5,
            'remaining_units': 7.5,
            'unit': 'usd_estimate',
          },
          'worker': {'enabled': true, 'interval_s': 30},
          'send_free_text': true,
        }
      );
    final s = await ApiAiRepository(w.client()).status(1);
    expect(w.last.headers['Authorization'], 'Bearer tok');
    expect(s.textProvider.model, 'claude-x');
    expect(s.textProvider.synthetic, isFalse);
    expect(s.videoProvider.synthetic, isTrue);
    expect(s.videoProvider.model, isNull);
    expect(s.budget.costCapUnits, 10);
    expect(s.budget.remainingUnits, 7.5);
    expect(s.worker.intervalS, 30);
    expect(s.sendFreeText, isTrue);
  });

  test('budget: PUT with the cap and the new figures back', () async {
    final w = Wire()
      ..answers['PUT /studies/1/ai/budget'] = (
        200,
        {'cost_cap_units': 12.5, 'spent_units': 2, 'remaining_units': 10.5, 'unit': 'usd_estimate'}
      );
    final b = await ApiAiRepository(w.client()).setBudget(1, 12.5);
    expect(w.last.method, 'PUT');
    expect(w.lastBody, {'cost_cap_units': 12.5});
    expect(b.remainingUnits, 10.5);
  });

  test('a 422 keeps the server message word for word', () async {
    final w = Wire()
      ..answers['POST /studies/1/ai/text-jobs'] = (
        422,
        {'detail': 'budget_exceeded: estimate 3.20 exceeds the remaining 1.00'}
      );
    await expectLater(
      ApiAiRepository(w.client()).createTextJob(1, const TextJobRequest(topic: 'x')),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'status', 422)
          .having((e) => e.message, 'message',
              'budget_exceeded: estimate 3.20 exceeds the remaining 1.00')),
    );
  });

  test('text job: numeric ids, blanks left out, defaults sent', () async {
    final w = Wire()..answers['POST /studies/1/ai/text-jobs'] = (201, jobJson(3));
    final job = await ApiAiRepository(w.client()).createTextJob(
      1,
      const TextJobRequest(
        assignmentId: '12',
        title: '  ',
        faceId: 'f1',
        voiceId: '',
      ),
    );
    expect(w.lastBody, {
      'assignment_id': 12,
      'interaction_points': 2,
      'length_seconds': 90,
      'face_id': 'f1',
    });
    expect(job.id, '3');
    expect(job.contentId, '7');
    expect(job.status, AiJobStatus.queued);
    expect(job.request['topic'], 'trains');
  });

  test('video jobs: a list of jobs, one per segment', () async {
    final w = Wire()
      ..answers['POST /studies/1/ai/video-jobs'] = (
        201,
        [
          {...jobJson(5), 'kind': 'video', 'segment_id': 's1'},
          {...jobJson(6), 'kind': 'video', 'segment_id': 's2'},
        ]
      );
    final jobs = await ApiAiRepository(w.client()).createVideoJobs(
      1,
      const VideoJobRequest(contentId: '7', segmentIds: ['s1', 's2'], voiceId: 'v'),
    );
    expect(w.lastBody, {
      'content_id': 7,
      'segment_ids': ['s1', 's2'],
      'voice_id': 'v',
    });
    expect(jobs.map((j) => (j.id, j.kind, j.segmentId)),
        [('5', 'video', 's1'), ('6', 'video', 's2')]);
  });

  test('jobs: filters go in the query string; actions post to the job', () async {
    final w = Wire()
      ..answers['GET /studies/1/ai/jobs'] = (200, [jobJson(2), jobJson(1)])
      ..answers['POST /studies/1/ai/jobs/2/cancel'] = (200, jobJson(2, status: 'cancelled'))
      ..answers['POST /studies/1/ai/jobs/1/retry'] = (200, jobJson(1))
      ..answers['POST /studies/1/ai/run'] =
          (200, {'processed': 3, 'succeeded': 2, 'failed': 1});
    final repo = ApiAiRepository(w.client());

    expect((await repo.jobs(1)).map((j) => j.id), ['2', '1']);
    expect(w.last.url.query, '');
    await repo.jobs(1, status: 'failed', contentId: '7');
    expect(w.last.url.queryParameters, {'status': 'failed', 'content_id': '7'});

    expect((await repo.cancel(1, '2')).status, AiJobStatus.cancelled);
    expect((await repo.retry(1, '1')).status, AiJobStatus.queued);
    final run = await repo.run(1);
    expect(w.last.url.queryParameters, {'max_jobs': '5'});
    expect((run.processed, run.succeeded, run.failed), (3, 2, 1));
  });

  test('content: text_reviewed is read and marked through its own endpoint',
      () async {
    final w = Wire()
      ..answers['POST /studies/1/content/7/text-reviewed'] = (
        200,
        {
          'id': 7,
          'title': 'AI draft: trains',
          'topic_tags': [],
          'face_id': '',
          'voice_id': '',
          'status': 'draft',
          'media_keys': ['s1.webm'],
          'missing_media': ['s1.webm'],
          'text_reviewed': true,
          'definition': {
            'start_segment': 's1',
            'post_segment': 's1',
            'segments': [
              {'id': 's1', 'text': 'Hi', 'media_key': 's1.webm', 'duration_s': 10}
            ],
            'comprehension': [],
          },
        }
      );
    final detail = await ApiContentRepository(w.client()).markTextReviewed(1, '7');
    expect(w.last.method, 'POST');
    expect(detail.summary.textReviewed, isTrue);
    expect(detail.summary.missingMedia, ['s1.webm']);
  });
}
