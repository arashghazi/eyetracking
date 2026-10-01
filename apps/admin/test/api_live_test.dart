import 'dart:convert';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:research_admin/features/live/data/api_live_repository.dart';
import 'package:research_admin/features/pilot/data/api_pilot_repository.dart';
import 'package:research_admin/features/protocols/data/api_protocols_repository.dart';

import 'live_fixtures.dart';
import 'pilot_fixtures.dart';

/// The wire of the step 7 staff endpoints against a canned HTTP client.
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
  Map<String, dynamic> get lastBody => jsonDecode(bodies.last) as Map<String, dynamic>;
}

void main() {
  group('live repository', () {
    test('status reads GET /studies/{id}/live/status', () async {
      final w = Wire()
        ..answers['GET /studies/3/live/status'] = (200, liveStatusJson());
      final s = await ApiLiveRepository(w.client()).status(3);
      expect(w.last.method, 'GET');
      expect(w.last.url.path, '/studies/3/live/status');
      expect(s.reply.name, 'fake');
      expect(s.openConversations, 2);
      expect(s.budget.remainingUnits, 3.75);
    });

    test('a refusal keeps the server message', () async {
      final w = Wire()
        ..answers['GET /studies/3/live/status'] =
            (403, {'detail': 'You are not a member of this study.'});
      expect(
        () => ApiLiveRepository(w.client()).status(3),
        throwsA(isA<ApiException>()
            .having((e) => e.isForbidden, 'forbidden', isTrue)
            .having((e) => e.message, 'message', 'You are not a member of this study.')),
      );
    });

    test('conversation reads GET /studies/{id}/sessions/{sid}/conversation', () async {
      final w = Wire()
        ..answers['GET /studies/3/sessions/21/conversation'] =
            (200, conversationJson(withText: true));
      final c = await ApiLiveRepository(w.client()).conversation(3, '21');
      expect(w.last.url.path, '/studies/3/sessions/21/conversation');
      expect(c, isNotNull);
      expect(c!.textKept, isTrue);
      expect(c.turns[1].text, 'I like steam trains');
      expect(c.outcome.participantTurns, 2);
    });

    test('404 means the session has no conversation', () async {
      final w = Wire()
        ..answers['GET /studies/3/sessions/21/conversation'] =
            (404, {'detail': 'this session has no live conversation'});
      expect(await ApiLiveRepository(w.client()).conversation(3, '21'), isNull);
    });

    test('any other failure is an error with the server wording', () async {
      final w = Wire()
        ..answers['GET /studies/3/sessions/21/conversation'] =
            (403, {'detail': 'You are not a member of this study.'});
      expect(
        () => ApiLiveRepository(w.client()).conversation(3, '21'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
    });

    test('the session id is encoded in the path', () async {
      final w = Wire()
        ..answers['GET /studies/3/sessions/a%20b/conversation'] = (404, {'detail': 'x'});
      expect(await ApiLiveRepository(w.client()).conversation(3, 'a b'), isNull);
      expect(w.last.url.path, '/studies/3/sessions/a%20b/conversation');
    });
  });

  group('pilot repository carries the conversation', () {
    test('the live monitor returns the conversation block next to the status', () async {
      final w = Wire()
        ..answers['GET /studies/1/sessions/21/live'] = (
          200,
          {
            'session_id': 21,
            'participant_code': 'P-001',
            'status': 'running',
            'conversation': {
              'status': 'open',
              'input_mode': 'typed',
              'turns_used': 2,
              'distress': 1,
              'redirects': 0,
              'last_turn': {'role': 'participant', 'flags': ['typed', 'distress'], 't_ms': 4200},
              'end_reason': null,
            },
          }
        );
      final reading = await ApiPilotRepository(w.client()).live(1, '21', first: true);
      expect(w.last.url.query, 'first=true');
      expect(reading.status.status, 'running');
      final c = reading.conversation!;
      expect(c.inputMode, LiveInputMode.typed);
      expect(c.turnsUsed, 2);
      expect(c.distress, 1);
      expect(c.lastTurn!.flags, ['typed', 'distress']);
      expect(c.lastTurn!.tMs, 4200);
    });

    test('a session without a conversation has none (null block)', () async {
      final w = Wire()
        ..answers['GET /studies/1/sessions/21/live'] =
            (200, {'session_id': 21, 'status': 'running', 'conversation': null});
      final reading = await ApiPilotRepository(w.client()).live(1, '21');
      expect(reading.conversation, isNull);
      final w2 = Wire()
        ..answers['GET /studies/1/sessions/21/live'] = (200, {'session_id': 21, 'status': 'running'});
      expect((await ApiPilotRepository(w2.client()).live(1, '21')).conversation, isNull);
    });

    test('the report rows keep their four conversation columns by session', () async {
      final base = {
        'study_id': 1,
        'settings': {'version': 3, 'values': settingsJson()},
        'rows': [
          {
            ...reportRow(21, 'P-001'),
            'conversation_turns': 4,
            'conversation_on_topic_share': 0.75,
            'conversation_distress': 1,
            'conversation_end_reason': 'turn_limit',
          },
          {
            ...reportRow(22, 'P-002'),
            'conversation_turns': null,
            'conversation_on_topic_share': null,
            'conversation_distress': null,
            'conversation_end_reason': null,
          },
          // An older service sends no such keys at all.
          reportRow(23, 'P-003'),
        ],
      };
      final w = Wire()..answers['GET /studies/1/pilot/report'] = (200, base);
      final data = await ApiPilotRepository(w.client()).report(1);

      expect(data.report.rows, hasLength(3));
      expect(data.report.settings.version, 3);
      final a = data.columnsFor('21');
      expect((a.turns, a.onTopicShare, a.distress, a.endReason), (4, 0.75, 1, 'turn_limit'));
      for (final id in ['22', '23', 'unknown']) {
        expect(data.columnsFor(id).isEmpty, isTrue, reason: id);
      }
    });
  });

  group('protocols repository, live path', () {
    test('creating sends the live section; reading brings it back', () async {
      const config = LiveProtocolConfig(
        maxTurns: 6,
        storeTranscript: true,
        inputModes: [LiveInputMode.speech],
      );
      final def = ProtocolDefinition(path: ProtocolPath.liveConversation, live: config);
      final w = Wire()
        ..answers['POST /studies/1/protocols'] = (
          200,
          {
            'id': 9,
            'name': 'Live',
            'version': 0,
            'status': 'draft',
            'path': 'live_conversation',
            'definition': def.toJson(),
          }
        )
        ..answers['GET /studies/1/protocols'] = (
          200,
          [
            {'id': 9, 'name': 'Live', 'version': 0, 'status': 'draft', 'path': 'live_conversation'},
          ]
        );
      final repo = ApiProtocolsRepository(w.client());

      final created = await repo.create(1, 'Live', def);
      expect(w.lastBody['name'], 'Live');
      final sent = w.lastBody['definition'] as Map<String, dynamic>;
      expect(sent['path'], 'live_conversation');
      expect(sent.containsKey('gradual'), isFalse);
      expect((sent['live'] as Map)['max_turns'], 6);
      expect((sent['live'] as Map)['input_modes'], ['speech']);
      expect(created.definition.path, ProtocolPath.liveConversation);
      expect(created.definition.live!.storeTranscript, isTrue);

      final list = await repo.list(1);
      expect(list.single.path, ProtocolPath.liveConversation);
    });
  });
}
