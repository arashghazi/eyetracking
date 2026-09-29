import 'dart:convert';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:research_admin/features/access_log/data/api_access_log_repository.dart';
import 'package:research_admin/features/analysis/data/api_analysis_repository.dart';
import 'package:research_admin/features/analysis/domain/analysis_filters.dart';
import 'package:research_admin/features/exports/data/api_exports_repository.dart';
import 'package:research_admin/features/participants/data/api_participants_repository.dart';
import 'package:research_admin/features/replay/data/api_replay_repository.dart';
import 'package:research_admin/features/studies/data/api_studies_repository.dart';

import 'fakes.dart';

/// The wire of the step 4 endpoints against a canned HTTP client. An answer
/// is text (sent as is) or JSON.
class Wire {
  final List<http.BaseRequest> requests = [];
  final List<String> bodies = [];
  final Map<String, Object> answers = {};

  ApiClient client() => ApiClient(
        baseUrl: 'http://api.test:8000',
        tokenStore: TokenStore()..save('tok'),
        httpClient: MockClient.streaming((request, body) async {
          requests.add(request);
          bodies.add(utf8.decode(await body.expand((c) => c).toList()));
          final key = '${request.method} ${request.url.path}';
          final answer = answers[key];
          final text = answer is String ? answer : jsonEncode(answer ?? {'detail': 'no route $key'});
          return http.StreamedResponse(
            Stream.value(utf8.encode(text)),
            answer == null ? 404 : 200,
            headers: {'content-type': answer is String ? 'text/csv' : 'application/json'},
          );
        }),
      );

  http.BaseRequest get last => requests.last;
}

void main() {
  test('replay: the signed clip links get the service address in front', () async {
    final w = Wire();
    w.answers['GET /studies/1/sessions/21/replay'] = sampleReplayJson();
    final bundle = await ApiReplayRepository(w.client()).load(1, '21');
    expect(w.last.headers['Authorization'], 'Bearer tok');
    expect(bundle.session.participantCode, 'P-001');
    expect(bundle.samples.length, greaterThan(100));
    expect(bundle.mediaEntries.first.url, 'http://api.test:8000/media/tok1');
    expect(bundle.layouts.first.layout.faceBox.w, 440);
  });

  test('replay: a missing session is an ApiException with the status', () async {
    final w = Wire();
    final repo = ApiReplayRepository(w.client());
    await expectLater(
      repo.load(1, '21'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
    );
  });

  test('analysis: the filters are the query string', () async {
    final w = Wire();
    w.answers['GET /studies/1/analysis'] = sampleAnalysisJson();
    final repo = ApiAnalysisRepository(w.client());
    final result = await repo.analysis(
      1,
      const AnalysisFilters(
        participant: 'P-001',
        path: 'gradual_face',
        protocolVersion: '2',
        device: 'web',
        from: '2026-09-01',
        to: '2026-10-31',
        qualities: {QualityGrade.ok, QualityGrade.review},
        includeSynthetic: true,
      ),
    );
    expect(w.last.url.query,
        'participant=P-001&path=gradual_face&protocol_version=2&device=web'
        '&from=2026-09-01&to=2026-10-31&quality=ok,review,exclude&include_synthetic=true');
    expect(w.last.url.queryParameters['quality'], 'ok,review,exclude');
    expect(result.trends.length, 2);
    expect(result.groups.first.participants, 1);
  });

  group('exports', () {
    test('sessions csv and json carry the same filters', () async {
      final w = Wire();
      w.answers['GET /studies/1/exports/sessions.csv'] = 'session_id,eye_share\n5,0.3\n';
      w.answers['GET /studies/1/exports/sessions.json'] = {'rows': []};
      final repo = ApiExportsRepository(w.client());
      const filters = AnalysisFilters(device: 'web', includeSynthetic: true);

      final csv = await repo.sessionsCsv(1, filters);
      expect(utf8.decode(csv), 'session_id,eye_share\n5,0.3\n');
      expect(w.last.url.query, 'device=web&quality=ok,review,exclude&include_synthetic=true');
      expect(w.last.headers['Accept'], '*/*');

      final json = await repo.sessionsJson(1, filters);
      expect(jsonDecode(utf8.decode(json)), {'rows': []});
      expect(w.last.url.query, 'device=web&quality=ok,review,exclude&include_synthetic=true');
    });

    test('samples and events are asked for by session', () async {
      final w = Wire();
      w.answers['GET /studies/1/exports/samples.csv'] = 't_ms,x,y\n';
      w.answers['GET /studies/1/exports/events.csv'] = 't_ms,type,payload_json\n';
      final repo = ApiExportsRepository(w.client());
      await repo.samplesCsv(1, '21');
      expect(w.last.url.path, '/studies/1/exports/samples.csv');
      expect(w.last.url.query, 'session_id=21');
      await repo.eventsCsv(1, '21');
      expect(w.last.url.path, '/studies/1/exports/events.csv');
      expect(w.last.url.query, 'session_id=21');
    });

    test('the dictionary is read whatever shape the server picks', () async {
      final w = Wire();
      w.answers['GET /studies/1/exports/data-dictionary.json'] = {
        'fields': [
          {'name': 'eye_share', 'type': 'float', 'unit': 'share', 'meaning': 'Eye share'},
        ],
      };
      final entries = await ApiExportsRepository(w.client()).dataDictionary(1);
      expect(entries.single.name, 'eye_share');
      expect(entries.single.unit, 'share');
    });

    test('an export failure is an ApiException with the message', () async {
      final w = Wire();
      final repo = ApiExportsRepository(w.client());
      await expectLater(
        repo.sessionsCsv(1, const AnalysisFilters()),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('no route'))),
      );
    });
  });

  test('access log: newest entries with a limit', () async {
    final w = Wire();
    w.answers['GET /studies/1/access-log'] = [
      {'at': '2026-09-30T09:15:00', 'user_id': 4, 'role': 'researcher', 'action': 'export_sessions', 'detail': 'sessions.csv'},
    ];
    final list = await ApiAccessLogRepository(w.client()).list(1, limit: 50);
    expect(w.last.url.query, 'limit=50');
    expect(list.single.action, 'export_sessions');
    expect(list.single.userId, '4');
  });

  group('studies', () {
    test('get reads the retention policy', () async {
      final w = Wire();
      w.answers['GET /studies/3'] = {'id': 3, 'name': 'Pilot', 'retention_policy': 'keep_coded'};
      final s = await ApiStudiesRepository(w.client()).get(3);
      expect(s.retentionPolicy, RetentionPolicy.keepCoded);
    });

    test('the policy is sent with PUT and the answer is the study', () async {
      final w = Wire();
      w.answers['PUT /studies/3'] = {'id': 3, 'name': 'Pilot', 'retention_policy': 'keep_coded'};
      final s = await ApiStudiesRepository(w.client()).setRetentionPolicy(3, 'keep_coded');
      expect(w.last.method, 'PUT');
      expect(jsonDecode(w.bodies.last), {'retention_policy': 'keep_coded'});
      expect(s.retentionPolicy, 'keep_coded');
    });

    test('an answer that is not the study is followed by a read', () async {
      final w = Wire();
      w.answers['PUT /studies/3'] = {'ok': true};
      w.answers['GET /studies/3'] = {'id': 3, 'name': 'Pilot', 'retention_policy': 'delete_all'};
      final s = await ApiStudiesRepository(w.client()).setRetentionPolicy(3, 'delete_all');
      expect(w.requests.map((r) => r.method), ['PUT', 'GET']);
      expect(s.retentionPolicy, 'delete_all');
    });
  });

  group('participant data deletion', () {
    test('DELETE with the code as confirmation; the code is encoded', () async {
      final w = Wire();
      w.answers['DELETE /studies/1/participants/P%20001/data'] = {
        'deleted': {'sessions': 2, 'samples': 900},
      };
      final result = await ApiParticipantsRepository(w.client()).deleteData(1, 'P 001', 'P 001');
      expect(w.last.method, 'DELETE');
      expect(w.last.url.path, '/studies/1/participants/P%20001/data');
      expect(jsonDecode(w.bodies.last), {'confirm': 'P 001'});
      expect(w.last.headers['Content-Type'], contains('application/json'));
      expect(result.deleted['samples'], 900);
    });

    test('an answer without a body is still a success', () async {
      final w = Wire();
      w.answers['DELETE /studies/1/participants/P-001/data'] = <String, Object>{};
      final result = await ApiParticipantsRepository(w.client()).deleteData(1, 'P-001', 'P-001');
      expect(result.deleted, isEmpty);
    });

    test('a wrong confirmation is refused by the server and says so', () async {
      final w = Wire();
      final repo = ApiParticipantsRepository(w.client());
      await expectLater(
        repo.deleteData(1, 'P-001', 'nope'),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
