import 'dart:convert';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const gradualJson = <String, dynamic>{
  'path': 'gradual_face',
  'baseline_seconds': 30,
  'post_seconds': 45,
  'comfort': {
    'scale_max': 5,
    'labels': ['Very uncomfortable', 'Uncomfortable', 'Neutral', 'Comfortable', 'Very comfortable'],
    'min_ok': 3,
    'ask_every_stage': true,
  },
  'progression': {
    'hold_on_invalid_share_above': 0.3,
    'easier_on_comfort_below_min': true,
    'stop_on_two_low_comfort': true,
  },
  'gradual': {
    'stages': [
      {
        'face_level': 0,
        'number_zone': 'outside',
        'trials': 6,
        'min_correct': 0.8,
        'response_mode': 'profile',
        'trial_seconds': 8,
      },
      {
        'face_level': 2,
        'number_zone': 'near_eyes',
        'trials': 4,
        'min_correct': 0.75,
        'response_mode': 'four_choice',
        'trial_seconds': 6.5,
      },
    ],
    'final_zone_limit': 'near_eyes',
    'allow_simultaneous_change': false,
    'real_face_media_url': null,
  },
};

const contentJson = <String, dynamic>{
  'start_segment': 's1',
  'post_segment': 's3',
  'segments': [
    {
      'id': 's1',
      'text': 'Hi {{display_name}}, today we talk about {{topic}}.',
      'media_key': 's1.webm',
      'duration_s': 20,
      'face_layout': {
        'face_box': [0.3, 0.1, 0.4, 0.8],
        'eye_region': [0.3, 0.25, 0.4, 0.2],
        'mouth_region': [0.3, 0.55, 0.4, 0.25],
      },
      'question': {
        'id': 'q1',
        'prompt': 'Which do you prefer?',
        'options': ['Trains', 'Planes'],
        'branches': {'Trains': 's2', 'Planes': 's2b'},
      },
    },
    {'id': 's2', 'text': '', 'media_key': 's2.webm', 'duration_s': 15, 'face_layout': null, 'question': null},
  ],
  'comprehension': [
    {
      'id': 'c1',
      'prompt': 'What colour was the train?',
      'options': ['Red', 'Blue'],
      'correct': 'Red',
    },
  ],
};

void main() {
  group('protocol', () {
    test('a gradual definition parses and writes back the same JSON', () {
      final def = ProtocolDefinition.maybeFromJson(gradualJson)!;
      expect(def.path, ProtocolPath.gradualFace);
      expect(def.baselineSeconds, 30);
      expect(def.postSeconds, 45);
      expect(def.comfort.scaleMax, 5);
      expect(def.comfort.minOk, 3);
      expect(def.comfort.labelFor(1), 'Very uncomfortable');
      expect(def.comfort.labelFor(5), 'Very comfortable');
      expect(def.comfort.labelFor(9), '9', reason: 'unlabelled values show the number');
      expect(def.gradual!.stages, hasLength(2));
      expect(def.gradual!.stages[1].numberZone, NumberZone.nearEyes);
      expect(def.gradual!.stages[1].responseMode, StageResponseMode.fourChoice);
      expect(def.gradual!.stages[1].trialSeconds, 6.5);
      expect(def.gradual!.finalZoneLimit, NumberZone.nearEyes);
      expect(def.gradual!.realFaceMediaUrl, isNull);
      expect(def.interest, isNull);
      expect(jsonDecode(jsonEncode(def.toJson())), gradualJson);
    });

    test('an interest definition carries its interaction points only', () {
      final def = ProtocolDefinition.maybeFromJson({
        'path': 'interest_conversation',
        'baseline_seconds': 20,
        'post_seconds': 20,
        'comfort': gradualJson['comfort'],
        'progression': gradualJson['progression'],
        'interest': {'interaction_points': 3},
      })!;
      expect(def.path, ProtocolPath.interestConversation);
      expect(def.interest!.interactionPoints, 3);
      expect(def.gradual, isNull);
      expect(def.toJson().containsKey('gradual'), isFalse);
      expect(def.toJson()['interest'], {'interaction_points': 3});
    });

    test('a real face url is kept, a blank one becomes null', () {
      final withUrl = GradualConfig.fromJson({
        'stages': const [],
        'real_face_media_url': 'https://media.test/face.png',
      });
      expect(withUrl.realFaceMediaUrl, 'https://media.test/face.png');
      expect(GradualConfig.fromJson({'stages': const [], 'real_face_media_url': ' '})
          .realFaceMediaUrl, isNull);
    });

    test('unknown paths are not accepted; unknown zones and modes fall back', () {
      expect(ProtocolDefinition.maybeFromJson({'path': 'other'}), isNull);
      expect(ProtocolDefinition.maybeFromJson('x'), isNull);
      expect(NumberZone.fromWire('nowhere'), NumberZone.outside);
      expect(StageResponseMode.fromWire('nope'), StageResponseMode.profile);
    });

    test('the starter definition for each path is complete', () {
      final g = ProtocolDefinition.starter(ProtocolPath.gradualFace);
      expect(g.gradual!.stages, isNotEmpty);
      expect(g.interest, isNull);
      final i = ProtocolDefinition.starter(ProtocolPath.interestConversation);
      expect(i.interest, isNotNull);
      expect(i.gradual, isNull);
      expect(g.comfort.labels, hasLength(g.comfort.scaleMax));
    });

    test('summary rows and details parse', () {
      final s = ProtocolSummary.fromJson({
        'id': 4,
        'name': 'Faces v1',
        'version': 2,
        'status': 'published',
        'path': 'gradual_face',
        'created_at': '2026-09-29T08:00:00',
        'published_at': '2026-09-30T08:00:00',
      });
      expect(s.id, '4');
      expect(s.isPublished, isTrue);
      expect(s.isDraft, isFalse);
      expect(s.path, ProtocolPath.gradualFace);
      final d = ProtocolDetail.fromJson({
        'id': 4,
        'name': 'Faces v1',
        'status': 'draft',
        'path': 'gradual_face',
        'definition': gradualJson,
      });
      expect(d.summary.isDraft, isTrue);
      expect(d.definition.gradual!.stages, hasLength(2));
    });

    test('a protocol reference inside a session carries its definition', () {
      final ref = ProtocolRef.maybeFromJson({
        'id': 4,
        'name': 'Faces v1',
        'version': 2,
        'path': 'gradual_face',
        'definition': gradualJson,
      })!;
      expect(ref.definition!.postSeconds, 45);
      expect(ref.path, ProtocolPath.gradualFace);
      expect(ProtocolRef.maybeFromJson(null), isNull);
    });
  });

  group('content', () {
    test('the authored definition round-trips', () {
      final def = ContentDefinition.fromJson(contentJson);
      expect(def.startSegment, 's1');
      expect(def.postSegment, 's3');
      expect(def.segments, hasLength(2));
      final s1 = def.segments.first;
      expect(s1.mediaKey, 's1.webm');
      expect(s1.question!.branches, {'Trains': 's2', 'Planes': 's2b'});
      expect(s1.faceLayout!.faceBox, const Box(0.3, 0.1, 0.4, 0.8));
      expect(def.segments[1].faceLayout, isNull);
      expect(def.segments[1].question, isNull);
      expect(def.comprehension.single.correct, 'Red');
      expect(jsonDecode(jsonEncode(def.toJson())), contentJson);
    });

    test('list rows report missing media', () {
      final row = ContentSummary.fromJson({
        'id': 7,
        'title': 'Trains',
        'topic_tags': ['trains', 'railways'],
        'face_id': 'f1',
        'voice_id': 'v1',
        'status': 'draft',
        'media_keys': ['s1.webm', 's2.webm'],
        'missing_media': ['s2.webm'],
      });
      expect(row.id, '7');
      expect(row.topicTags, ['trains', 'railways']);
      expect(row.missingMedia, ['s2.webm']);
      expect(row.isDraft, isTrue);
      expect(row.isApproved, isFalse);
    });

    test('the participant copy has signed urls and no answers', () {
      final content = PersonalizedContent.fromJson({
        'title': 'Trains',
        'face_id': 'f1',
        'voice_id': 'v1',
        'start_segment': 's1',
        'post_segment': 's3',
        'segments': [
          {
            'id': 's1',
            'text': 'Hi Sam',
            'media_url': 'http://media.test/media/tok123',
            'duration_s': 20,
            'face_layout': contentJson['segments'][0]['face_layout'],
            'question': {'id': 'q1', 'prompt': 'Which?', 'options': ['A', 'B']},
          },
        ],
        'comprehension': [
          {'id': 'c1', 'prompt': 'Colour?', 'options': ['Red', 'Blue']},
        ],
      });
      expect(content.segment('s1')!.mediaUrl, 'http://media.test/media/tok123');
      expect(content.segment('s1')!.question!.options, ['A', 'B']);
      expect(content.segment('nope'), isNull);
      expect(content.segment(null), isNull);
      expect(content.comprehension.single.prompt, 'Colour?');
      expect(content.postSegment, 's3');
    });

    test('a normalized layout maps onto a rectangle in screen pixels', () {
      const layout = NormalizedFaceLayout(
        faceBox: Box(0.5, 0.0, 0.5, 1.0),
        eyeRegion: Box(0.5, 0.2, 0.5, 0.2),
        mouthRegion: Box(0.6, 0.6, 0.3, 0.2),
      );
      final mapped = layout.toStimulusLayout(
        const ScreenInfo(w: 1000, h: 800, dpr: 2),
        const Box(100, 200, 400, 300),
      );
      expect(mapped.screen.dpr, 2);
      expect(mapped.faceBox, const Box(300, 200, 200, 300));
      expect(mapped.eyeRegion, const Box(300, 260, 200, 60));
      expect(mapped.mouthRegion.x, closeTo(340, 1e-9));
      expect(mapped.mouthRegion.y, closeTo(380, 1e-9));
    });

    test('object-fit contain: letterbox, pillarbox and the exact fit', () {
      // Wide video in a tall box: bars above and below.
      expect(containedVideoRect(const Box(0, 0, 100, 100), 200, 100),
          const Box(0, 25, 100, 50));
      // Tall video in a wide box: bars left and right.
      expect(containedVideoRect(const Box(10, 20, 200, 100), 50, 100),
          const Box(85, 20, 50, 100));
      // Same aspect: the whole box.
      expect(containedVideoRect(const Box(5, 5, 160, 90), 1920, 1080),
          const Box(5, 5, 160, 90));
    });
  });

  group('assignments', () {
    test('parse and label', () {
      final a = Assignment.fromJson({
        'id': 9,
        'order_index': 2,
        'status': 'content_pending',
        'protocol': {'id': 4, 'name': 'Talk', 'version': 1, 'path': 'interest_conversation'},
        'topic': 'trains',
        'topic_free_text': 'the old steam ones',
        'content_id': null,
        'content_title': null,
        'created_at': '2026-09-29T08:00:00',
      });
      expect(a.id, '9');
      expect(a.orderIndex, 2);
      expect(a.status, AssignmentStatus.contentPending);
      expect(a.isInterest, isTrue);
      expect(a.canStartSession, isFalse);
      expect(a.topic, 'trains');
      expect(a.topicFreeText, 'the old steam ones');
      expect(a.contentId, isNull);
      expect(assignmentStatusLabel(a.status), 'Content being prepared');
      for (final s in [AssignmentStatus.ready, AssignmentStatus.inProgress]) {
        expect(Assignment.fromJson({'id': 1, 'status': s, 'protocol': {'id': 1, 'name': 'x'}})
            .canStartSession, isTrue);
      }
    });
  });

  group('practice wire', () {
    test('a trial is written as the contract asks', () {
      const t = TrialRecord(
        stageIndex: 1,
        trialIndex: 3,
        tMs: 12345,
        numberShown: '42',
        zone: 'near_eyes',
        x: 512.4,
        y: 300.6,
        faceLevel: 2,
        response: '42',
        responseMs: 830,
      );
      expect(t.toJson(), {
        'stage_index': 1,
        'trial_index': 3,
        't_ms': 12345,
        'number_shown': '42',
        'zone': 'near_eyes',
        'position': {'x': 512.0, 'y': 301.0},
        'face_level': 2,
        'response': '42',
        'response_ms': 830,
      });
      const missed = TrialRecord(
        stageIndex: 0, trialIndex: 0, tMs: 1, numberShown: '7', zone: 'outside',
        x: 1, y: 1, faceLevel: 0,
      );
      expect(missed.toJson()['response'], isNull);
      expect(missed.toJson()['response_ms'], isNull);
    });

    test('a stage decision never advances on an unknown word', () {
      final d = StageDecision.fromJson({
        'decision': 'advance',
        'next_stage_index': 2,
        'reason': 'criteria_met',
        'correct_ratio': 0.83,
        'invalid_share': 0.1,
        'trials': 6,
      });
      expect(d.kind, StageDecisionKind.advance);
      expect(d.nextStageIndex, 2);
      expect(d.correctRatio, 0.83);
      expect(StageDecision.fromJson({'decision': 'teleport'}).kind, StageDecisionKind.hold);
      expect(StageDecision.fromJson({'decision': 'complete', 'next_stage_index': null})
          .nextStageIndex, isNull);
    });

    test('answers: request and result', () {
      const a = AnswerRequest(
        segmentId: 's1', questionId: 'q1', kind: AnswerKind.interaction,
        option: 'Trains', tMs: 900,
      );
      expect(a.toJson(), {
        'segment_id': 's1',
        'question_id': 'q1',
        'kind': 'interaction',
        'option': 'Trains',
        't_ms': 900,
      });
      expect(AnswerResult.fromJson({'correct': null, 'next_segment_id': 's2'}).nextSegmentId, 's2');
      expect(AnswerResult.fromJson({'correct': true, 'next_segment_id': null}).correct, isTrue);
      expect(AnswerResult.fromJson({'next_segment_id': ''}).nextSegmentId, isNull);
    });

    test('the session request names its assignment as a number', () {
      const request = SessionCreateRequest(
        device: DeviceInfo(platform: 'web'),
        screen: ScreenInfo(w: 800, h: 600),
        camera: CameraInfo(w: 640, h: 480),
        gazeModel: GazeInfo(modelId: 'm', modelVersion: '1', synthetic: false),
        assignmentId: '17',
      );
      expect(request.toJson()['assignment_id'], 17);
      expect(const SessionCreateRequest(
        device: DeviceInfo(platform: 'web'),
        screen: ScreenInfo(w: 800, h: 600),
        camera: CameraInfo(w: 640, h: 480),
        gazeModel: GazeInfo(modelId: 'm', modelVersion: '1', synthetic: false),
      ).toJson().containsKey('assignment_id'), isFalse);
    });
  });

  group('session summary with outcomes', () {
    const summaryJson = <String, dynamic>{
      'id': 11,
      'status': 'ended',
      'assignment_id': 17,
      'protocol': {'id': 4, 'name': 'Faces v1', 'version': 2, 'path': 'gradual_face', 'definition': gradualJson},
      'outcomes': {
        'gaze': {'baseline_eye_share': 0.2, 'post_eye_share': 0.35, 'evaluable': true, 'reason': null},
        'comprehension': {'answered': 3, 'correct': 2, 'share': 0.67},
        'number_task': {'trials': 12, 'correct': 10, 'share': 0.83, 'stages_completed': 2},
        'comfort': {'answers': 3, 'min': 3, 'mean': 3.67, 'low_count': 0, 'pauses': 1, 'ended_early': false},
        'improvement': {
          'eligible': true,
          'result': true,
          'criteria': {'eye_share_up': true, 'comfort_not_worse': true, 'comprehension_maintained': true},
          'reason': null,
        },
      },
      'stages': [
        {
          'stage_index': 0,
          'decision': 'advance',
          'reason': 'criteria_met',
          'correct_ratio': 0.83,
          'invalid_share': 0.05,
          'comfort_value': 4,
          'trials': 6,
        },
      ],
    };

    test('parses outcomes, stages and the protocol', () {
      final s = SessionSummary.fromJson(summaryJson);
      expect(s.assignmentId, '17');
      expect(s.protocol!.path, ProtocolPath.gradualFace);
      final o = s.outcomes!;
      expect(o.gaze.evaluable, isTrue);
      expect(o.gaze.baselineEyeShare, 0.2);
      expect(o.comprehension.answered, 3);
      expect(o.numberTask.stagesCompleted, 2);
      expect(o.comfort.mean, 3.67);
      expect(o.comfort.pauses, 1);
      expect(o.improvement.result, isTrue);
      expect(o.improvement.eyeShareUp, isTrue);
      expect(s.stages.single.decision, 'advance');
      expect(s.stages.single.comfortValue, 4);
    });

    test('an old session without outcomes stays valid', () {
      final s = SessionSummary.fromJson({'id': 1, 'status': 'ended'});
      expect(s.outcomes, isNull);
      expect(s.stages, isEmpty);
      expect(s.protocol, isNull);
      expect(s.assignmentId, isNull);
    });

    test('a result of null means it cannot be judged, with the reason', () {
      final o = SessionOutcomes.maybeFromJson({
        'gaze': {'evaluable': false, 'reason': 'synthetic_estimator'},
        'improvement': {
          'eligible': false,
          'result': null,
          'criteria': {'eye_share_up': null, 'comfort_not_worse': null, 'comprehension_maintained': null},
          'reason': 'synthetic_estimator',
        },
      })!;
      expect(o.improvement.result, isNull);
      expect(o.improvement.eligible, isFalse);
      expect(o.gaze.baselineEyeShare, isNull);
      expect(o.comfort.answers, 0);
      expect(outcomeReasonLabel('synthetic_estimator'),
          'The development estimator makes no measurement claims.');
      expect(outcomeReasonLabel('something_odd_happened'), 'Something odd happened.');
      expect(outcomeReasonLabel(null), '');
    });

    test('the researcher detail carries trials, answers and comfort answers', () {
      final d = SessionDetail.fromJson({
        ...summaryJson,
        'participant_code': 'P-001',
        'trials': [
          {
            'stage_index': 0, 'trial_index': 1, 't_ms': 5000, 'number_shown': '42',
            'zone': 'outside', 'face_level': 0, 'response': '42', 'response_ms': 700, 'correct': true,
          },
        ],
        'answers': [
          {
            'segment_id': 's1', 'question_id': 'q1', 'kind': 'interaction',
            'option': 'Trains', 'correct': null, 't_ms': 900, 'next_segment_id': 's2',
          },
        ],
        'comfort_answers': [
          {'t_ms': 8000, 'payload': {'value': 4, 'stage_index': 0}},
          {'t_ms': 9000, 'value': 5, 'segment': 'post'},
        ],
      });
      expect(d.trials.single.correct, isTrue);
      expect(d.trials.single.numberShown, '42');
      expect(d.answers.single.nextSegmentId, 's2');
      expect(d.answers.single.correct, isNull);
      expect(d.comfortAnswers.map((c) => c.value), [4, 5]);
      expect(d.comfortAnswers.first.stageIndex, 0);
      expect(d.comfortAnswers.last.segment, 'post');
      expect(d.summary.outcomes, isNotNull);
    });
  });

  group('signed media paths', () {
    test('a root-relative path gets the service address, absolute urls do not', () {
      final api = ApiClient(baseUrl: 'http://api.test:8000/');
      expect(api.resolveUrl('/media/abc.def'), 'http://api.test:8000/media/abc.def');
      expect(api.resolveUrl('https://cdn.test/media/abc?sig=1'),
          'https://cdn.test/media/abc?sig=1');
      expect(api.resolveUrl('//cdn.test/x'), '//cdn.test/x');
      expect(api.resolveUrl('blob:abc'), 'blob:abc');
      expect(api.resolveUrl(''), '');
    });
  });

  group('errors and upload', () {
    http.Response jsonResponse(int status, Object body) => http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
        );

    test('a 422 keeps its body: missing media at the top or inside detail', () async {
      for (final body in [
        {'detail': 'Media is missing.', 'missing_media': ['a.webm', 'b.webm']},
        {
          'detail': {'message': 'Media is missing.', 'missing_media': ['a.webm', 'b.webm']},
        },
      ]) {
        final api = ApiClient(
          baseUrl: 'http://api.test',
          httpClient: MockClient((_) async => jsonResponse(422, body)),
        );
        try {
          await api.postObject('/x');
          fail('should have thrown');
        } on ApiException catch (e) {
          expect(e.statusCode, 422);
          expect(e.message, 'Media is missing.');
          expect(e.missingMedia, ['a.webm', 'b.webm']);
        }
      }
    });

    test('the list can also come from the message text', () {
      const e = ApiException('missing media: s1.webm, s2.webm', statusCode: 422);
      expect(e.missingMedia, ['s1.webm', 's2.webm']);
      expect(const ApiException('missing media:', statusCode: 422).missingMedia, isEmpty);
    });

    test('an error without missing media has an empty list', () {
      expect(const ApiException('x', statusCode: 400).missingMedia, isEmpty);
      expect(const ApiException('x', body: {'detail': 'y'}).missingMedia, isEmpty);
    });

    test('uploadFile sends a multipart body with the token and reports progress',
        () async {
      late http.BaseRequest seen;
      late List<int> bytes;
      final tokens = TokenStore()..save('tok');
      final api = ApiClient(
        baseUrl: 'http://api.test',
        tokenStore: tokens,
        httpClient: MockClient.streaming((request, body) async {
          seen = request;
          bytes = await body.expand((c) => c).toList();
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode(
                {'key': 's1.webm', 'content_type': 'video/webm', 'size': 200000}))),
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final progress = <(int, int)>[];
      final result = await api.uploadFile(
        '/studies/1/content/2/media/s1.webm',
        bytes: List.filled(200000, 7),
        filename: 's1.webm',
        contentType: 'video/webm',
        onProgress: (sent, total) => progress.add((sent, total)),
      );

      expect(result['key'], 's1.webm');
      expect(seen.method, 'POST');
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(seen.headers['Content-Type'], startsWith('multipart/form-data; boundary='));
      final text = latin1.decode(bytes);
      expect(text, contains('name="file"; filename="s1.webm"'));
      expect(text, contains('Content-Type: video/webm'));
      expect(bytes.length, seen.contentLength);
      // Progress ends at the total and never goes backwards.
      expect(progress.last.$1, progress.last.$2);
      expect(progress.length, greaterThan(2), reason: 'in several chunks');
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i].$1, greaterThanOrEqualTo(progress[i - 1].$1));
      }
    });

    test('a failed upload throws the server message', () async {
      final api = ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient.streaming((request, body) async {
          await body.drain<void>();
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({'detail': 'File is too large.'}))),
            413,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      expect(
        () => api.uploadFile('/x', bytes: [1], filename: 'a.mp4', contentType: 'video/mp4'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'File is too large.')),
      );
    });
  });
}
