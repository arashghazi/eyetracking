import 'dart:convert';
import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:eyetracking_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const layoutJson = {
  'screen': {'w': 1440, 'h': 900, 'dpr': 1},
  'face_box': [500, 100, 440, 600],
  'eye_region': [520, 220, 400, 120],
  'mouth_region': [560, 480, 320, 100],
};

Map<String, dynamic> replayJson() => {
      'session': {
        'id': 7,
        'participant_code': 'P-001',
        'status': 'ended',
        'created_at': '2026-09-29T08:00:00',
        'synthetic': true,
        'quality': {
          'grade': 'review',
          'reasons': ['validation_not_passed', 'uncertain_share_above_0.2'],
        },
        'protocol': {'name': 'Faces v1', 'version': 2, 'path': 'gradual_face'},
      },
      'screen': {'w': 1440, 'h': 900, 'dpr': 1.25},
      'segments': [
        {'label': 'baseline', 'started_ms': 1000, 'ended_ms': 11000},
        {'label': 'practice', 'started_ms': 12000, 'ended_ms': 30000},
      ],
      'layouts': [
        {'id': 1, 'segment': 'baseline', 'stage_index': null, 'layout': layoutJson, 'from_ms': 1000, 'to_ms': 9000},
        {'id': 2, 'segment': 'practice', 'stage_index': 0, 'layout': layoutJson, 'from_ms': 12000, 'to_ms': 20000},
      ],
      'samples': [
        for (var t = 1000; t <= 9000; t += 100)
          [t, 700.0 + (t - 1000) / 100, 300.0, 0.9, t % 300 == 0 ? 0 : 2],
        [9100, null, null, 0.1, 4],
        [12000, 720.0, 340.0, 0.8, 1],
        [12100, 721.0, 341.0, 0.8, 1],
        [20000, 700.0, 300.0, 0.7, 3],
      ],
      'events': [
        {'t_ms': 1000, 'type': 'segment_start', 'payload': {'segment': 'baseline'}},
        {'t_ms': 20500, 'type': 'pause', 'payload': null},
      ],
      'trials': [
        {'stage_index': 0, 'trial_index': 1, 't_ms': 15000, 'number_shown': '42', 'zone': 'outside', 'position': {'x': 200, 'y': 150}, 'face_level': 0, 'response': '42', 'correct': true, 'response_ms': 1500},
        {'stage_index': 0, 'trial_index': 0, 't_ms': 12500, 'number_shown': '17', 'zone': 'outside', 'position': [210, 160], 'face_level': 0, 'response': null, 'correct': null, 'response_ms': null},
      ],
      'answers': [
        {'segment_id': 's1', 'question_id': 'q1', 'kind': 'interaction', 'option': 'Trains', 'correct': null, 't_ms': 12000},
      ],
      'quality_strip': [
        {'from_ms': 1000, 'to_ms': 2000, 'valid_share': 1.0},
        {'from_ms': 2000, 'to_ms': 3000, 'valid_share': null},
      ],
      'gaps': [
        {'from_ms': 9200, 'to_ms': 11900},
      ],
      'pauses': [
        {'from_ms': 20500, 'to_ms': 22000},
      ],
      'media': [
        {'segment_id': 's2', 'media_key': 's2.webm', 'start_ms': 25000, 'url': '/media/tok2'},
        {'segment_id': 's1', 'media_key': 's1.webm', 'start_ms': 12000, 'url': '/media/tok1'},
      ],
    };

void main() {
  group('session quality', () {
    test('parses grade and reasons and phrases them for people', () {
      final q = SessionQuality.maybeFromJson({
        'grade': 'review',
        'reasons': ['validation_not_passed', 'uncertain_share_above_0.2', 'missing_share_above_0.125'],
      })!;
      expect(q.grade, 'review');
      expect(q.isReview, isTrue);
      expect(q.reasonsText.split('\n'), [
        'Regional validation not passed',
        'Uncertain share above 20 %',
        'Missing share above 12.5 %',
      ]);
      expect(q.shortReason, 'Regional validation not passed (+2)');
      expect(qualityGradeLabel('exclude'), 'Exclude');
      expect(qualityReasonLabel('synthetic_estimator'), contains('synthetic'));
      expect(qualityReasonLabel('something_new'), 'Something new');
      expect(SessionQuality.maybeFromJson(null), isNull);
    });

    test('is part of the session summary and the list row', () {
      final summary = SessionSummary.fromJson({
        'id': 1,
        'status': 'ended',
        'quality': {'grade': 'exclude', 'reasons': ['no_calibration']},
      });
      expect(summary.quality!.isExcluded, isTrue);
      final row = SessionListItem.fromJson({
        'id': 2,
        'participant_code': 'P-1',
        'status': 'ended',
        'quality': {'grade': 'ok', 'reasons': []},
      });
      expect(row.quality!.isOk, isTrue);
      expect(row.quality!.reasonsText, 'No quality problem found.');
      expect(SessionListItem.fromJson({'id': 3}).quality, isNull);
    });
  });

  group('replay bundle', () {
    final bundle = ReplayBundle.fromJson(replayJson());

    test('reads every part of the contract', () {
      expect(bundle.session.participantCode, 'P-001');
      expect(bundle.session.quality!.grade, 'review');
      expect(bundle.session.protocol!.version, 2);
      expect(bundle.screen.w, 1440);
      expect(bundle.segments.map((s) => s.label), ['baseline', 'practice']);
      expect(bundle.layouts.last.stageIndex, 0);
      expect(bundle.layouts.first.layout.eyeRegion.w, 400);
      expect(bundle.events.length, 2);
      expect(bundle.answers.single.option, 'Trains');
      expect(bundle.qualityStrip.last.validShare, isNull);
      expect(bundle.gaps.single.toMs, 11900);
      expect(bundle.pauses.single.fromMs, 20500);
      expect(bundle.durationMs, 30000);
      expect(bundle.hasMedia, isTrue);
    });

    test('decodes compact samples only when asked', () {
      final s = bundle.samples;
      expect(s.length, 85);
      final first = s[0];
      expect(first.tMs, 1000);
      expect(first.x, 700);
      expect(first.hasPosition, isTrue);
      expect(first.regionName, isNotEmpty);
      final uncertain = s[s.indexAtOrBefore(9100)];
      expect(uncertain.x, isNull);
      expect(uncertain.hasPosition, isFalse);
      expect(uncertain.regionCode, ReplayRegion.uncertain);
      expect(ReplayRegion.label(ReplayRegion.eye), 'Eyes');
      expect(ReplayRegion.label(ReplayRegion.mouth), 'Mouth');
      expect(ReplayRegion.label(3), 'Outside the face');
    });

    test('finds a sample by time and cuts a window', () {
      final s = bundle.samples;
      expect(s.indexAtOrBefore(500), -1);
      expect(s.indexAtOrBefore(1050), 0);
      expect(s.latestAt(1250)!.tMs, 1200);
      expect(s.latestAt(5000, maxAgeMs: 50)!.tMs, 5000);
      expect(s.latestAt(15000), isNull, reason: 'the last sample is too old');
      final w = s.window(1000, 1300);
      expect([for (final x in w) x.tMs], [1000, 1100, 1200, 1300]);
      expect(s.window(500, 900), isEmpty);
    });

    test('unsorted rows are put in time order', () {
      final samples = ReplaySamples([
        [300, 1.0, 1.0, 1.0, 0],
        [100, 2.0, 2.0, 1.0, 0],
        [200, 3.0, 3.0, 1.0, 0],
      ]);
      expect([for (var i = 0; i < 3; i++) samples.tMsAt(i)], [100, 200, 300]);
    });

    test('the layout in use follows the samples and the segment', () {
      expect(bundle.layoutAt(500), isNull, reason: 'before everything');
      expect(bundle.layoutAt(5000)!.id, '1');
      expect(bundle.layoutAt(10500)!.id, '1', reason: 'baseline still open');
      expect(bundle.layoutAt(11500), isNull, reason: 'between segments');
      expect(bundle.layoutAt(12000)!.stageIndex, 0);
      expect(bundle.layoutAt(25000)!.id, '2', reason: 'practice still open');
      expect(bundle.layoutAt(31000), isNull, reason: 'after the last segment');
    });

    test('a trial is active from its start until it is answered or replaced', () {
      expect(bundle.trialAt(12000), isNull);
      expect(bundle.trialAt(12500)!.numberShown, '17');
      expect(bundle.trialAt(12500)!.x, 210, reason: 'position as [x, y]');
      // Unanswered: ends when the next trial starts.
      expect(bundle.trialAt(14999)!.numberShown, '17');
      expect(bundle.trialAt(15000)!.numberShown, '42');
      expect(bundle.trialAt(15000)!.x, 200, reason: 'position as {x, y}');
      // Answered after 1500 ms.
      expect(bundle.trialAt(16499)!.numberShown, '42');
      expect(bundle.trialAt(16500), isNull);
    });

    test('an unanswered last trial ends after the default time', () {
      final b = ReplayBundle(
        session: const ReplaySession(id: '1', participantCode: 'P', status: 'ended'),
        screen: const ScreenInfo(w: 100, h: 100),
        trials: const [ReplayTrial(stageIndex: 0, trialIndex: 0, tMs: 1000, numberShown: '5')],
      );
      expect(b.trialAt(1000 + ReplayBundle.unansweredTrialMs - 1), isNotNull);
      expect(b.trialAt(1000 + ReplayBundle.unansweredTrialMs), isNull);
    });

    test('gaps and pauses are found by time; a gap hides the sample', () {
      expect(bundle.gapAt(9100), isNull);
      expect(bundle.gapAt(9200), isNotNull);
      expect(bundle.gapAt(11899), isNotNull);
      expect(bundle.gapAt(11900), isNull);
      expect(bundle.pauseAt(21000)!.toMs, 22000);
      expect(bundle.pauseAt(22000), isNull);
      expect(bundle.sampleAt(9500), isNull, reason: 'inside a gap');
      expect(bundle.sampleAt(5000)!.tMs, 5000);
    });

    test('media entries are ordered and end at the next clip or the segment',
        () {
      final m = bundle.mediaEntries;
      expect([for (final e in m) e.segmentId], ['s1', 's2']);
      expect(bundle.mediaEndMs(m[0]), 25000, reason: 'the next clip starts');
      expect(bundle.mediaEndMs(m[1]), 30000, reason: 'the practice segment ends');
      expect(bundle.mediaAt(11000), isNull);
      expect(bundle.mediaAt(12000)!.url, '/media/tok1');
      expect(bundle.mediaAt(24999)!.url, '/media/tok1');
      expect(bundle.mediaAt(25000)!.url, '/media/tok2');
      expect(bundle.mediaAt(30001), isNull);
    });

    test('a clip the server could not resolve has no link', () {
      final b = ReplayBundle.fromJson({
        'media': [
          {'segment_id': 's1', 'media_key': 's1', 'start_ms': 1000, 'url': null},
          {'segment_id': 's2', 'media_key': 's2.webm', 'start_ms': 5000, 'url': '/media/t'},
        ],
      });
      expect(b.mediaEntries[0].hasUrl, isFalse);
      expect(b.mediaEntries[0].url, '');
      expect(b.mediaEntries[1].hasUrl, isTrue);
    });

    test('an empty bundle is harmless', () {
      final b = ReplayBundle.fromJson({});
      expect(b.durationMs, 0);
      expect(b.hasSamples, isFalse);
      expect(b.layoutAt(0), isNull);
      expect(b.trialAt(0), isNull);
      expect(b.mediaAt(0), isNull);
      expect(b.sampleAt(0), isNull);
    });
  });

  group('analysis models', () {
    final json = {
      'filters': {'include_synthetic': false},
      'rows': [
        {
          'session_id': 5,
          'participant_code': 'P-001',
          'created_at': '2026-09-29T08:00:00',
          'path': 'gradual_face',
          'protocol_name': 'Faces v1',
          'protocol_version': 2,
          'device_platform': 'web',
          'estimator': 'l2cs-1',
          'synthetic': false,
          'quality': 'review',
          'quality_reasons': ['ended_early'],
          'baseline_eye_share': 0.2,
          'post_eye_share': 0.32,
          'eye_share_delta': 0.12,
          'comfort_mean': 4.5,
          'improvement': true,
          'group_key': 'web|2|l2cs-1|s',
          'demographics': {'age': 34},
        },
        {'session_id': 6, 'participant_code': 'P-002'},
      ],
      'groups': [
        {'group_key': 'web|2|l2cs-1|s', 'device_platform': 'web', 'protocol_version': 2, 'estimator': 'l2cs-1', 'screen_bucket': '1280x720', 'stimulus_bucket_px': 400, 'sessions': 3, 'participants': 2},
      ],
      'trends': [
        {
          'participant_code': 'P-001',
          'group_key': 'web|2|l2cs-1|s',
          'points': [
            {'session_id': 9, 'created_at': '2026-10-02T08:00:00', 'baseline_eye_share': null, 'post_eye_share': null, 'comfort_mean': 3.0},
            {'session_id': 5, 'created_at': '2026-09-29T08:00:00', 'baseline_eye_share': 0.2, 'post_eye_share': 0.32, 'comfort_mean': 4.5, 'quality': 'ok'},
          ],
        },
      ],
      'excluded': 4,
      'note': 'Sessions from different groups are never pooled into one trend by default.',
    };

    test('reads rows, groups, trends and the note', () {
      final a = AnalysisResponse.fromJson(json);
      expect(a.rows.length, 2);
      final r = a.rows.first;
      expect(r.sessionId, '5');
      expect(r.eyeShareDelta, 0.12);
      expect(r.improvement, isTrue);
      expect(r.qualityInfo!.grade, 'review');
      expect(r.qualityInfo!.reasons, ['ended_early']);
      expect(r.demographics['age'], 34);
      expect(a.rows.last.eyeShareDelta, isNull);
      expect(a.groups.single.sessions, 3);
      expect(a.groups.single.stimulusBucket, '400');
      expect(a.excluded, 4);
      expect(a.note, startsWith('Sessions from different groups'));
    });

    test('numbers the server sends as text are read too', () {
      // The parts of a group key are text on the wire; the export joins the
      // quality reasons with ";".
      final a = AnalysisResponse.fromJson({
        'rows': [
          {
            'session_id': 1,
            'participant_code': 'P-1',
            'protocol_version': '3',
            'quality': 'review',
            'quality_reasons': 'ended_early;validation_not_passed',
            'eye_share_delta': '0.25',
          },
          {'session_id': 2, 'quality': 'ok', 'quality_reasons': ''},
        ],
        'groups': [
          {
            'group_key': 'web|2|l2cs-1|1280|400',
            'device_platform': 'web',
            'protocol_version': '2',
            'estimator': 'l2cs-1',
            'screen_bucket': '1280',
            'stimulus_bucket_px': '400',
            'sessions': 3,
            'participants': 2,
          },
        ],
      });
      expect(a.rows.first.protocolVersion, 3);
      expect(a.rows.first.qualityReasons, ['ended_early', 'validation_not_passed']);
      expect(a.rows.first.qualityInfo!.reasons.length, 2);
      expect(a.rows.first.eyeShareDelta, 0.25);
      expect(a.rows.last.qualityReasons, isEmpty);
      expect(a.groups.single.protocolVersion, 2);
      expect(a.groups.single.stimulusBucket, '400');
      expect(a.groups.single.screenBucket, '1280');
    });

    test('trend points are ordered by date and know when they are not evaluable',
        () {
      final t = AnalysisResponse.fromJson(json).trends.single;
      expect([for (final p in t.points) p.sessionId], ['5', '9']);
      expect(t.points.first.evaluable, isTrue);
      expect(t.points.last.evaluable, isFalse);
    });

    test('access log detail may be text or an object', () {
      final text = AccessLogEntry.fromJson({'at': '2026-09-29T08:00:00', 'user_id': 3, 'role': 'analyst', 'action': 'export', 'detail': 'sessions.csv'});
      expect(text.detail, 'sessions.csv');
      expect(text.userId, '3');
      final object = AccessLogEntry.fromJson({'at': 'x', 'action': 'replay', 'detail': {'session_id': 5, 'ok': true}});
      expect(object.detail, 'session_id: 5, ok: true');
      expect(AccessLogEntry.fromJson({'at': 'x', 'action': 'a'}).detail, '');
    });

    test('the data dictionary is read from a list, a wrapper or a map', () {
      final entry = {'name': 'eye_share', 'type': 'float', 'unit': 'share 0-1', 'meaning': 'Share of time on the eyes'};
      for (final shape in <Object>[
        [entry],
        {'fields': [entry]},
        {'columns': [entry]},
        {'eye_share': {'type': 'float', 'unit': 'share 0-1', 'meaning': 'Share of time on the eyes'}},
      ]) {
        final list = DictionaryEntry.listFromJson(shape);
        expect(list.single.name, 'eye_share');
        expect(list.single.unit, 'share 0-1');
        expect(list.single.meaning, startsWith('Share'));
      }
      expect(DictionaryEntry.listFromJson('nonsense'), isEmpty);
    });
  });

  group('study, erase and my data', () {
    test('a study carries its retention policy (default delete_all)', () {
      final s = StudyInfo.fromJson({'id': 3, 'name': 'Pilot', 'retention_policy': 'keep_coded'});
      expect(s.retentionPolicy, RetentionPolicy.keepCoded);
      expect(StudyInfo.fromJson({'id': 1, 'name': 'A'}).retentionPolicy, RetentionPolicy.deleteAll);
      expect(s.copyWith(retentionPolicy: 'delete_all').retentionPolicy, 'delete_all');
      expect(RetentionPolicy.label('keep_coded'), isNot(RetentionPolicy.label('delete_all')));
    });

    test('the erase result lists what was deleted', () {
      final r = EraseResult.fromJson({
        'policy': 'delete_all',
        'deleted': {'sessions': 2, 'samples': 900, 'consents': 1},
        'identity_removed': true,
      });
      expect(r.deleted['samples'], 900);
      expect(r.identityRemoved, isTrue);
    });

    test('my data is counted: sessions, samples, events, consents', () {
      final counts = MyDataCounts.fromJson({
        'consents': [{}, {}],
        'sessions': [
          {'samples': [[1, 1, 1, 1, 0], [2, 1, 1, 1, 0]], 'events': [{}, {}, {}]},
          {'samples': [[1, 1, 1, 1, 0]], 'events': []},
        ],
      });
      expect(counts.sessions, 2);
      expect(counts.samples, 3);
      expect(counts.events, 3);
      expect(counts.consents, 2);
      expect(MyDataCounts.fromJson(null).sessions, 0);
    });
  });

  group('ApiClient downloads and delete', () {
    test('getBytes returns the body untouched and asks for any type', () async {
      late http.BaseRequest seen;
      final api = ApiClient(
        baseUrl: 'http://api.test',
        tokenStore: TokenStore()..save('tok'),
        httpClient: MockClient((request) async {
          seen = request;
          return http.Response.bytes(utf8.encode('a,b\n1,2\n'), 200,
              headers: {'content-type': 'text/csv'});
        }),
      );
      final bytes = await api.getBytes('/studies/1/exports/sessions.csv?x=1');
      expect(utf8.decode(bytes), 'a,b\n1,2\n');
      expect(bytes, isA<Uint8List>());
      expect(seen.url.toString(), 'http://api.test/studies/1/exports/sessions.csv?x=1');
      expect(seen.headers['Accept'], '*/*');
      expect(seen.headers['Authorization'], 'Bearer tok');
    });

    test('getBytes turns a failure into a readable ApiException', () async {
      var unauthorized = 0;
      final api = ApiClient(
        baseUrl: 'http://api.test',
        tokenStore: TokenStore()..save('tok'),
        onUnauthorized: () => unauthorized++,
        httpClient: MockClient((request) async {
          if (request.url.path.contains('gone')) {
            return http.Response(jsonEncode({'detail': 'You are not a member.'}), 403);
          }
          return http.Response('', 401);
        }),
      );
      await expectLater(
        api.getBytes('/gone'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'You are not a member.')),
      );
      await expectLater(api.getBytes('/other'), throwsA(isA<ApiException>()));
      expect(unauthorized, 1);
    });

    test('delete sends the confirmation as a JSON body', () async {
      late http.BaseRequest seen;
      String? body;
      final api = ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient((request) async {
          seen = request;
          body = request.body;
          return json(200, {'deleted': {'sessions': 1}});
        }),
      );
      final result = await api.deleteObject('/studies/1/participants/P-001/data', {'confirm': 'P-001'});
      expect(seen.method, 'DELETE');
      expect(jsonDecode(body!), {'confirm': 'P-001'});
      expect((result['deleted'] as Map)['sessions'], 1);
    });
  });

  group('video remote control', () {
    test('commands reach an attached player and are re-applied after a load',
        () {
      final controller = VideoStageController();
      final player = RecordingVideoPlayer();
      controller.seek(3.5); // before any player exists: remembered
      controller.setRate(2);
      controller.play();
      expect(controller.attached, isFalse);
      controller.attach(player);
      controller.applyPending();
      expect(player.commands, ['rate:2.0', 'seek:3.50', 'play']);

      player.commands.clear();
      controller.pause();
      controller.seek(-4);
      expect(player.commands, ['pause', 'seek:0.00']);

      player.commands.clear();
      controller.applyPending();
      expect(player.commands, ['rate:2.0', 'seek:0.00', 'pause']);

      controller.detach(player);
      expect(controller.attached, isFalse);
      controller.play(); // no player: no error
    });

    testWidgets('the fake stage attaches the player and stays quiet without autoplay',
        (tester) async {
      final controller = VideoStageController()..seek(2);
      final player = RecordingVideoPlayer();
      var ended = 0;
      var playing = 0;
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: FakeVideoStage(
            player: player,
            config: VideoStageConfig(
              url: '/media/x',
              autoplay: false,
              controller: controller,
              onEnded: () => ended++,
              onPlaying: () => playing++,
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(controller.attached, isTrue);
      expect(player.commands, ['rate:1.0', 'seek:2.00', 'pause']);
      expect(ended, 0);
      expect(playing, 0);
      await tester.pumpWidget(const SizedBox());
      expect(controller.attached, isFalse);
    });
  });

  test('saveFile outside the browser saves nothing and says so', () async {
    expect(await saveFile(Uint8List(3), 'a.csv', 'text/csv'), isFalse);
  });
}

http.Response json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
