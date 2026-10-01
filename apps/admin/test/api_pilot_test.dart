import 'dart:convert';
import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:research_admin/features/ai/data/api_ai_repository.dart';
import 'package:research_admin/features/measurement_settings/data/api_measurement_settings_repository.dart';
import 'package:research_admin/features/pilot/data/api_pilot_repository.dart';

import 'pilot_fixtures.dart';

/// The wire of the step 6 endpoints against a canned HTTP client.
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
          final payload = answer.$2;
          return http.StreamedResponse(
            Stream.value(payload is List<int> ? payload : utf8.encode(jsonEncode(payload))),
            answer.$1,
            headers: {'content-type': payload is List<int> ? 'text/csv' : 'application/json'},
          );
        }),
      );

  http.BaseRequest get last => requests.last;
  Object? get lastBody => bodies.last.isEmpty ? null : jsonDecode(bodies.last);
  String get lastQuery => last.url.query;
}

void main() {
  group('settings history and versions', () {
    test('history is read newest first', () async {
      final w = Wire()
        ..answers['GET /studies/1/measurement-settings/history'] = (
          200,
          [
            {
              'version': 2,
              'values': settingsJson(correct: 0.7),
              'rationale': 'Too strict',
              'changed_by': 7,
              'created_at': '2026-09-29T10:00:00',
            },
            {
              'version': 1,
              'values': settingsJson(),
              'rationale': 'Defaults; no change recorded yet',
              'changed_by': null,
              'created_at': null,
            },
          ]
        );
      final list = await ApiPilotRepository(w.client()).settingsHistory(1);
      expect(w.last.headers['Authorization'], 'Bearer tok');
      expect(list.map((v) => v.version), [2, 1]);
      expect(list.first.values.validationMinCorrect, 0.7);
      expect(list.last.createdAt, isNull);
    });

    test('load reads the version and the quality thresholds', () async {
      final w = Wire()
        ..answers['GET /studies/1/measurement-settings'] =
            (200, {...settingsJson(), 'version': 3});
      final s = await ApiMeasurementSettingsRepository(w.client()).load(1);
      expect(s.version, 3);
      expect(s.qualityMaxMissingShare, 0.2);
    });

    test('save sends the six values and the trimmed rationale', () async {
      final w = Wire()
        ..answers['PUT /studies/1/measurement-settings'] =
            (200, {...settingsJson(correct: 0.7), 'version': 2});
      final repo = ApiMeasurementSettingsRepository(w.client());
      final saved = await repo.save(
        1,
        const MeasurementSettings(validationMinCorrect: 0.7),
        rationale: '  Pilot showed too many fails  ',
      );
      expect(saved.version, 2);
      expect(w.lastBody, {
        'validation_min_correct': 0.7,
        'validation_max_uncertain': 0.2,
        'min_region_to_error_ratio': 2.0,
        'gaze_conf_threshold': 0.5,
        'calibration_points': 9,
        'allow_continue_without_validation': true,
        'rationale': 'Pilot showed too many fails',
      });
    });

    test('an empty rationale is not sent', () async {
      final w = Wire()
        ..answers['PUT /studies/1/measurement-settings'] =
            (200, {...settingsJson(), 'version': 1});
      final repo = ApiMeasurementSettingsRepository(w.client());
      await repo.save(1, MeasurementSettings.defaults, rationale: '   ');
      expect((w.lastBody as Map).containsKey('rationale'), isFalse);
      await repo.save(1, MeasurementSettings.defaults);
      expect((w.lastBody as Map).containsKey('rationale'), isFalse);
    });

    test('saveChanges sends only the named fields with the rationale', () async {
      final w = Wire()
        ..answers['PUT /studies/1/measurement-settings'] =
            (200, {...settingsJson(correct: 0.7), 'version': 2});
      final saved = await ApiMeasurementSettingsRepository(w.client()).saveChanges(
        1,
        {'validation_min_correct': 0.7, 'quality_max_missing_share': 0.3},
        rationale: 'Loosened for the pilot',
      );
      expect(saved.version, 2);
      expect(w.lastBody, {
        'validation_min_correct': 0.7,
        'quality_max_missing_share': 0.3,
        'rationale': 'Loosened for the pilot',
      });
    });
  });

  group('threshold review', () {
    test('posts the changes and the synthetic switch', () async {
      final w = Wire()
        ..answers['POST /studies/1/pilot/threshold-review'] = (
          200,
          {
            'current': {'version': 1, 'values': settingsJson()},
            'candidate': {'values': settingsJson(correct: 0.7), 'changes': {'validation_min_correct': 0.7}},
            'sessions': 1,
            'rows': [],
            'notes': ['n'],
          }
        );
      final repo = ApiPilotRepository(w.client());
      final r = await repo.thresholdReview(
        1,
        changes: {'validation_min_correct': 0.7},
        includeSynthetic: true,
      );
      expect(w.lastBody, {
        'changes': {'validation_min_correct': 0.7},
        'include_synthetic': true,
      });
      expect(r.changes, {'validation_min_correct': 0.7});
      expect(r.notes, ['n']);

      await repo.thresholdReview(1);
      expect(w.lastBody, {'changes': {}, 'include_synthetic': false});
    });

    test('a 422 keeps the server text', () async {
      final w = Wire()
        ..answers['POST /studies/1/pilot/threshold-review'] =
            (422, {'detail': 'unknown settings: colour'});
      expect(
        () => ApiPilotRepository(w.client()).thresholdReview(1, changes: {'colour': 1}),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'unknown settings: colour')
            .having((e) => e.statusCode, 'status', 422)),
      );
    });
  });

  group('observations and live monitor', () {
    test('lists and adds observations', () async {
      final w = Wire()
        ..answers['GET /studies/1/sessions/21/observations'] = (
          200,
          [
            {
              'id': 1,
              'session_id': 21,
              'author_id': 7,
              'category': 'comfort',
              'severity': 'info',
              'text': 'Looked away',
              't_ms': null,
              'created_at': '2026-09-30T09:30:00',
            },
          ]
        )
        ..answers['POST /studies/1/sessions/21/observations'] = (
          201,
          {
            'id': 2,
            'session_id': 21,
            'author_id': 7,
            'category': 'technical',
            'severity': 'major',
            'text': 'Lost the face',
            't_ms': 4200,
            'created_at': '2026-09-30T09:31:00',
          }
        );
      final repo = ApiPilotRepository(w.client());
      final list = await repo.observations(1, '21');
      expect(list.single.text, 'Looked away');

      final created = await repo.addObservation(
        1,
        '21',
        const ObservationRequest(
          category: 'technical',
          severity: 'major',
          text: 'Lost the face',
          tMs: 4200,
        ),
      );
      expect(created.id, '2');
      expect(w.lastBody, {
        'category': 'technical',
        'severity': 'major',
        'text': 'Lost the face',
        't_ms': 4200,
      });
    });

    test('reads the active sessions and sends first only when asked', () async {
      final w = Wire()
        ..answers['GET /studies/1/pilot/active'] = (
          200,
          [
            {
              'session_id': 21,
              'participant_code': 'P-001',
              'status': 'running',
              'created_at': '2026-09-30T09:00:00',
              'device_platform': 'windows',
              'protocol_id': 4,
              'last_event': null,
            },
          ]
        )
        ..answers['GET /studies/1/sessions/21/live'] = (
          200,
          {'session_id': 21, 'participant_code': 'P-001', 'status': 'running'}
        );
      final repo = ApiPilotRepository(w.client());
      final active = await repo.activeSessions(1);
      expect(active.single.participantCode, 'P-001');
      expect(active.single.lastEvent, isNull);

      await repo.live(1, '21', first: true);
      expect(w.lastQuery, 'first=true');
      final live = await repo.live(1, '21');
      expect(w.lastQuery, 'first=false');
      expect(live.status.status, 'running');
      expect(live.conversation, isNull);
    });

    test('a 403 shows the server message', () async {
      final w = Wire()
        ..answers['GET /studies/1/pilot/active'] =
            (403, {'detail': 'you are not a member of this study'});
      expect(
        () => ApiPilotRepository(w.client()).activeSessions(1),
        throwsA(isA<ApiException>().having((e) => e.isForbidden, 'forbidden', isTrue)
            .having((e) => e.message, 'message', 'you are not a member of this study')),
      );
    });
  });

  group('debrief form', () {
    test('reads the form', () async {
      final w = Wire()
        ..answers['GET /studies/1/debrief-form'] = (
          200,
          {
            'version': 0,
            'enabled': false,
            'saved': false,
            'questions': [
              {'key': 'comfort_overall', 'type': 'scale', 'prompt': 'How?', 'scale_max': 5, 'labels': [], 'required': true},
            ],
          }
        );
      final form = await ApiPilotRepository(w.client()).debriefForm(1);
      expect(form.version, 0);
      expect(form.saved, isFalse);
      expect(form.questions.single.scaleMax, 5);
    });

    test('saves questions and the switch, or the switch alone', () async {
      final w = Wire()
        ..answers['PUT /studies/1/debrief-form'] =
            (200, {'version': 3, 'enabled': true, 'saved': true, 'questions': []});
      final repo = ApiPilotRepository(w.client());
      final form = await repo.saveDebriefForm(
        1,
        questions: [
          const DebriefQuestion(
            key: 'room',
            type: DebriefQuestionType.choice,
            prompt: 'Which room?',
            options: ['A', 'B'],
          ),
        ],
        enabled: true,
      );
      expect(form.version, 3);
      expect(w.lastBody, {
        'questions': [
          {'key': 'room', 'type': 'choice', 'prompt': 'Which room?', 'required': false, 'options': ['A', 'B']},
        ],
        'enabled': true,
      });

      await repo.saveDebriefForm(1, enabled: false);
      expect(w.lastBody, {'enabled': false});
    });
  });

  group('research eye tracker', () {
    test('imports a file as multipart with every field', () async {
      final w = Wire()
        ..answers['POST /studies/1/sessions/21/reference'] = (
          201,
          {
            'id': 5,
            'session_id': 21,
            'source': 'Tobii Pro Spark',
            'settings': {'alignment': 'given_offset'},
            'sample_count': 100,
            'valid_count': 90,
            'uploaded_by': 7,
            'created_at': '2026-09-30T10:00:00',
          }
        );
      final recording = await ApiPilotRepository(w.client()).importReference(
        1,
        '21',
        bytes: Uint8List.fromList(utf8.encode('time\tx\ty\n0\t1\t2\n')),
        filename: 'tobii.tsv',
        request: const ReferenceImportRequest(
          source: 'Tobii Pro Spark',
          timeColumn: 'time',
          xColumn: 'x',
          yColumn: 'y',
          timeUnit: ReferenceTimeUnit.us,
          offset: 1500,
          coordSpace: ReferenceCoordSpace.norm,
          delimiter: '\t',
          autoAlignWindowMs: 2000,
        ),
      );
      expect(recording.id, '5');
      expect(recording.sampleCount, 100);
      expect(w.last.method, 'POST');
      expect(w.last.headers['Authorization'], 'Bearer tok');
      expect(w.last.headers['Content-Type'], startsWith('multipart/form-data; boundary='));
      final body = w.bodies.last;
      for (final part in [
        'name="source"\r\n\r\nTobii Pro Spark\r\n',
        'name="time_column"\r\n\r\ntime\r\n',
        'name="x_column"\r\n\r\nx\r\n',
        'name="y_column"\r\n\r\ny\r\n',
        'name="time_unit"\r\n\r\nus\r\n',
        'name="offset"\r\n\r\n1500\r\n',
        'name="coord_space"\r\n\r\nnorm\r\n',
        'name="origin_x"\r\n\r\n0\r\n',
        'name="delimiter"\r\n\r\n\t\r\n',
        'name="auto_align_window_ms"\r\n\r\n2000\r\n',
        'name="file"; filename="tobii.tsv"',
        'Content-Type: text/tab-separated-values',
        'time\tx\ty\n0\t1\t2\n',
      ]) {
        expect(body, contains(part));
      }
      expect(body.contains('name="valid_column"'), isFalse,
          reason: 'optional fields are left out');
    });

    test('a file the server cannot read is a 422 with its text', () async {
      final w = Wire()
        ..answers['POST /studies/1/sessions/21/reference'] = (
          422,
          {'detail': "time column 'time' not found; the file has columns: t, x, y"}
        );
      expect(
        () => ApiPilotRepository(w.client()).importReference(
          1,
          '21',
          bytes: Uint8List.fromList([1, 2, 3]),
          filename: 'a.csv',
          request: const ReferenceImportRequest(
            source: 's',
            timeColumn: 'time',
            xColumn: 'x',
            yColumn: 'y',
          ),
        ),
        throwsA(isA<ApiException>().having(
          (e) => e.message,
          'message',
          "time column 'time' not found; the file has columns: t, x, y",
        )),
      );
    });

    test('lists recordings and compares with the tolerance', () async {
      final w = Wire()
        ..answers['GET /studies/1/sessions/21/reference'] = (
          200,
          [
            {
              'id': 901,
              'session_id': 21,
              'source': 'Tobii',
              'settings': {'alignment': 'estimated_from_data', 'estimated_shift_ms': 40},
              'sample_count': 5,
              'valid_count': 4,
              'uploaded_by': 7,
              'created_at': '2026-09-30T10:00:00',
            },
          ]
        )
        ..answers['GET /studies/1/sessions/21/reference/901/compare'] = (
          200,
          {
            'tolerance_ms': 120,
            'webcam_samples': 10,
            'paired_classified': 8,
            'distance_px': {'n': 0},
            'bias_px': {'x': null, 'y': null},
            'region_agreement': null,
            'cohen_kappa': null,
            'confusion': {'rows_webcam_columns_reference': {}},
            'eye_region': {'precision': null, 'recall': null},
            'segments': [],
            'caveats': ['c'],
          }
        );
      final repo = ApiPilotRepository(w.client());
      final list = await repo.references(1, '21');
      expect(list.single.alignmentEstimated, isTrue);
      final c = await repo.compare(1, '21', '901', toleranceMs: 120);
      expect(w.lastQuery, 'tolerance_ms=120');
      expect(c.toleranceMs, 120);
      expect(c.cohenKappa, isNull);
      expect(c.caveats, ['c']);
      await repo.compare(1, '21', '901');
      expect(w.lastQuery, 'tolerance_ms=40');
    });
  });

  group('pilot report', () {
    test('reads the report and the CSV for both synthetic settings', () async {
      final csv = utf8.encode('﻿session_id,participant_code\n21,P-001\n');
      final w = Wire()
        ..answers['GET /studies/1/pilot/report'] = (
          200,
          {
            'study_id': 1,
            'settings': {'version': 3, 'values': settingsJson()},
            'sessions': 1,
            'participants': 1,
            'validation': {'validated': 1, 'passed': 1},
            'quality': {'ok': 1, 'review': 0, 'exclude': 0},
            'rows': [],
          }
        )
        ..answers['GET /studies/1/pilot/report.csv'] = (200, csv);
      final repo = ApiPilotRepository(w.client());
      final report = await repo.report(1);
      expect(w.lastQuery, 'include_synthetic=false');
      expect(report.report.settings.version, 3);
      expect(report.report.validationPassed, 1);

      await repo.report(1, includeSynthetic: true);
      expect(w.lastQuery, 'include_synthetic=true');

      final bytes = await repo.reportCsv(1, includeSynthetic: true);
      expect(w.last.url.path, '/studies/1/pilot/report.csv');
      expect(w.lastQuery, 'include_synthetic=true');
      expect(bytes, csv);
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF], reason: 'the BOM arrives untouched');
    });
  });

  group('AI free text', () {
    test('sends send_free_text alone and returns the stored value', () async {
      final w = Wire()
        ..answers['PUT /studies/1/ai/budget'] = (
          200,
          {
            'cost_cap_units': 10,
            'spent_units': 0,
            'remaining_units': 10,
            'unit': 'usd_estimate',
            'send_free_text': true,
          }
        );
      final repo = ApiAiRepository(w.client());
      expect(await repo.setSendFreeText(1, true), isTrue);
      expect(w.lastBody, {'send_free_text': true});
      expect((w.lastBody as Map).containsKey('cost_cap_units'), isFalse);
    });

    test('a refusal is thrown with the server text', () async {
      final w = Wire()
        ..answers['PUT /studies/1/ai/budget'] =
            (403, {'detail': 'administrator role required'});
      expect(
        () => ApiAiRepository(w.client()).setSendFreeText(1, false),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'administrator role required')),
      );
    });
  });
}
