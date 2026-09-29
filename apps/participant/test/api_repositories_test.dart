import 'dart:convert';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:participant_app/features/assignments/data/api_assignments_repository.dart';
import 'package:participant_app/features/session/data/api_session_repository.dart';

/// The wire of the step 3 endpoints, checked against a canned HTTP client:
/// what the repositories send and how they read the answers.
class Recorder {
  final List<http.Request> requests = [];
  final Map<String, Object> answers = {};

  ApiClient client() => ApiClient(
        baseUrl: 'http://api.test:8000',
        tokenStore: TokenStore()..save('tok'),
        httpClient: MockClient((request) async {
          requests.add(request);
          final key = '${request.method} ${request.url.path}';
          final body = answers[key];
          if (body == null) return http.Response('{"detail":"no route $key"}', 404);
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

  Map<String, dynamic> bodyOf(int i) =>
      jsonDecode(requests[i].body) as Map<String, dynamic>;
}

void main() {
  group('assignments', () {
    test('list, topic and content', () async {
      final r = Recorder();
      r.answers['GET /me/assignments'] = [
        {
          'id': 5,
          'order_index': 0,
          'status': 'pending_topic',
          'protocol': {'id': 3, 'name': 'Talk', 'version': 1, 'path': 'interest_conversation'},
          'topic': null,
          'topic_free_text': null,
          'content_id': null,
          'content_title': null,
          'created_at': '2026-09-29T08:00:00',
        },
      ];
      r.answers['POST /me/assignments/5/topic'] = {
        'id': 5,
        'order_index': 0,
        'status': 'content_pending',
        'protocol': {'id': 3, 'name': 'Talk', 'version': 1, 'path': 'interest_conversation'},
        'topic': 'trains',
        'topic_free_text': 'steam ones',
      };
      final repo = ApiAssignmentsRepository(r.client());

      final list = await repo.list();
      expect(list.single.status, AssignmentStatus.pendingTopic);
      expect(list.single.isInterest, isTrue);
      expect(r.requests.single.headers['Authorization'], 'Bearer tok');

      final updated = await repo.submitTopic('5', topic: 'trains', freeText: '  steam ones ');
      expect(updated.status, AssignmentStatus.contentPending);
      expect(r.bodyOf(1), {'topic': 'trains', 'free_text': 'steam ones'});

      await repo.submitTopic('5', topic: 'trains');
      expect(r.bodyOf(2), {'topic': 'trains'}, reason: 'no free text, none sent');
    });

    test('a signed /media path gets the service address; absolute urls stay',
        () async {
      final r = Recorder();
      r.answers['GET /me/assignments/5/content'] = {
        'title': 'Trains',
        'face_id': 'f1',
        'voice_id': 'v1',
        'start_segment': 's1',
        'post_segment': 's2',
        'segments': [
          {
            'id': 's1',
            'text': 'Hi Sam',
            'media_url': '/media/abc.def-ghi',
            'duration_s': 20,
            'face_layout': {
              'face_box': [0.3, 0.1, 0.4, 0.8],
              'eye_region': [0.3, 0.25, 0.4, 0.2],
              'mouth_region': [0.3, 0.55, 0.4, 0.25],
            },
            'question': {'id': 'q1', 'prompt': 'Which?', 'options': ['A', 'B']},
          },
          {
            'id': 's2',
            'text': '',
            'media_url': 'https://cdn.test/media/xyz?sig=1',
            'duration_s': 5,
            'face_layout': null,
            'question': null,
          },
          {'id': 's3', 'media_url': null, 'duration_s': 5},
        ],
        'comprehension': [
          {'id': 'c1', 'prompt': 'Colour?', 'options': ['Red', 'Blue']},
        ],
      };
      final content = await ApiAssignmentsRepository(r.client()).content('5');
      expect(content.segment('s1')!.mediaUrl, 'http://api.test:8000/media/abc.def-ghi');
      expect(content.segment('s2')!.mediaUrl, 'https://cdn.test/media/xyz?sig=1');
      expect(content.segment('s3')!.mediaUrl, '', reason: 'a file that was never uploaded');
      expect(content.segment('s1')!.faceLayout, isNotNull);
      expect(content.segment('s1')!.question!.options, ['A', 'B']);
      expect(content.comprehension.single.id, 'c1');
    });

    test('a 404 (content not ready yet) is an ApiException', () async {
      final r = Recorder();
      expect(
        () => ApiAssignmentsRepository(r.client()).content('9'),
        throwsA(isA<ApiException>().having((e) => e.isNotFound, 'notFound', isTrue)),
      );
    });
  });

  group('session', () {
    test('create names the assignment and reads the protocol with its '
        'definition; a signed real-face path is made reachable', () async {
      final r = Recorder();
      r.answers['POST /me/sessions'] = {
        'id': 11,
        'status': 'created',
        'assignment_id': 5,
        'protocol': {
          'id': 3,
          'name': 'Faces',
          'version': 2,
          'path': 'gradual_face',
          'definition': {
            'path': 'gradual_face',
            'baseline_seconds': 30,
            'post_seconds': 30,
            'comfort': {'scale_max': 5, 'labels': kDefaultComfortLabels, 'min_ok': 3, 'ask_every_stage': true},
            'progression': {},
            'gradual': {
              'stages': [
                {'face_level': 3, 'number_zone': 'outside', 'trials': 4, 'min_correct': 0.8, 'response_mode': 'profile', 'trial_seconds': 8},
              ],
              'final_zone_limit': 'near_eyes',
              'allow_simultaneous_change': false,
              'real_face_media_url': '/media/face-token',
            },
          },
        },
      };
      final repo = ApiSessionRepository(r.client());
      final summary = await repo.create(const SessionCreateRequest(
        device: DeviceInfo(platform: 'web'),
        screen: ScreenInfo(w: 800, h: 600),
        camera: CameraInfo(w: 640, h: 480),
        gazeModel: GazeInfo(modelId: 'm', modelVersion: '1', synthetic: false),
        assignmentId: '5',
      ));

      expect(r.bodyOf(0)['assignment_id'], 5);
      expect(summary.assignmentId, '5');
      final def = summary.protocol!.definition!;
      expect(def.path, ProtocolPath.gradualFace);
      expect(def.gradual!.stages.single.faceLevel, 3);
      expect(def.gradual!.realFaceMediaUrl, 'http://api.test:8000/media/face-token');
    });

    test('layout carries the stage index only for a practice stage', () async {
      final r = Recorder();
      r.answers['POST /me/sessions/11/layout'] = {'layout_id': 1};
      final repo = ApiSessionRepository(r.client());
      const layout = StimulusLayout(
        screen: ScreenInfo(w: 800, h: 600),
        faceBox: Box(300, 100, 200, 300),
        eyeRegion: Box(320, 145, 160, 105),
        mouthRegion: Box(340, 265, 120, 120),
      );
      await repo.postLayout('11', SessionSegmentName.practice, layout, stageIndex: 2);
      await repo.postLayout('11', SessionSegmentName.baseline, layout);

      expect(r.bodyOf(0)['segment'], 'practice');
      expect(r.bodyOf(0)['stage_index'], 2);
      expect((r.bodyOf(0)['layout'] as Map)['face_box'], [300.0, 100.0, 200.0, 300.0]);
      expect(r.bodyOf(1)['segment'], 'baseline');
      expect(r.bodyOf(1).containsKey('stage_index'), isFalse);
    });

    test('trials, stage result and answers', () async {
      final r = Recorder();
      r.answers['POST /me/sessions/11/trials'] = {'stored': 2, 'correct': 1};
      r.answers['POST /me/sessions/11/stage-result'] = {
        'decision': 'hold',
        'next_stage_index': 0,
        'reason': 'accuracy',
        'correct_ratio': 0.5,
        'invalid_share': 0.0,
        'trials': 2,
      };
      r.answers['POST /me/sessions/11/answers'] = {'correct': null, 'next_segment_id': 's2'};
      final repo = ApiSessionRepository(r.client());

      final ack = await repo.postTrials('11', const [
        TrialRecord(
          stageIndex: 0, trialIndex: 0, tMs: 1000, numberShown: '42', zone: 'outside',
          x: 100.4, y: 200.6, faceLevel: 0, response: '42', responseMs: 700,
        ),
        TrialRecord(
          stageIndex: 0, trialIndex: 1, tMs: 5000, numberShown: '7', zone: 'outside',
          x: 90, y: 180, faceLevel: 0,
        ),
      ]);
      expect(ack.stored, 2);
      expect(ack.correct, 1);
      final trials = r.bodyOf(0)['trials'] as List;
      expect(trials, hasLength(2));
      expect((trials[0] as Map)['number_shown'], '42');
      expect((trials[0] as Map)['position'], {'x': 100.0, 'y': 201.0});
      expect((trials[1] as Map)['response'], isNull);

      final decision = await repo.stageResult('11', 0, comfortValue: 4);
      expect(r.bodyOf(1), {'stage_index': 0, 'comfort_value': 4});
      expect(decision.kind, StageDecisionKind.hold);
      expect(decision.reason, 'accuracy');
      await repo.stageResult('11', 1);
      expect(r.bodyOf(2), {'stage_index': 1}, reason: 'no comfort value, none sent');

      final result = await repo.postAnswer(
        '11',
        const AnswerRequest(
          segmentId: 's1', questionId: 'q1', kind: AnswerKind.interaction,
          option: 'Trains', tMs: 900,
        ),
      );
      expect(result.nextSegmentId, 's2');
      expect(r.bodyOf(3)['kind'], 'interaction');
    });

    test('comfort answers are events with the scale value', () async {
      final r = Recorder();
      r.answers['POST /me/sessions/11/events'] = {'id': 11, 'status': 'running'};
      await ApiSessionRepository(r.client()).postEvent(
        '11',
        SessionEventType.comfortAnswer,
        tMs: 61000,
        payload: {'value': 4, 'stage_index': 1},
      );
      expect(r.bodyOf(0), {
        't_ms': 61000,
        'type': 'comfort_answer',
        'payload': {'value': 4, 'stage_index': 1},
      });
    });

    test('a session summary with outcomes and stages parses', () async {
      final r = Recorder();
      r.answers['GET /me/sessions/11'] = {
        'id': 11,
        'status': 'ended',
        'outcomes': {
          'gaze': {'evaluable': false, 'reason': 'synthetic_estimator'},
          'comprehension': {'answered': 0, 'correct': 0, 'share': null},
          'number_task': {'trials': 6, 'correct': 5, 'share': 0.83, 'stages_completed': 1},
          'comfort': {'answers': 2, 'min': 3, 'mean': 3.5, 'low_count': 0, 'pauses': 0, 'ended_early': false},
          'improvement': {'eligible': false, 'result': null, 'criteria': {}, 'reason': 'synthetic_estimator'},
        },
        'stages': [
          {'stage_index': 0, 'decision': 'complete', 'reason': 'all_stages_done', 'correct_ratio': 0.83, 'invalid_share': 0.0, 'comfort_value': 4, 'trials': 6},
        ],
      };
      final s = await ApiSessionRepository(r.client()).summary('11');
      expect(s.outcomes!.numberTask.correct, 5);
      expect(s.outcomes!.improvement.result, isNull);
      expect(s.stages.single.decision, 'complete');
    });
  });
}
