import 'dart:convert';
import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:participant_app/features/session/data/api_live_repository.dart';

/// The wire of the step 7 participant endpoints, checked against a canned
/// HTTP client: what the repository sends and how it reads the answers.
class Wire {
  final List<http.Request> requests = [];
  final Map<String, ({int status, Object body})> answers = {};

  ApiClient client() => ApiClient(
        baseUrl: 'http://api.test:8000',
        tokenStore: TokenStore()..save('tok'),
        httpClient: MockClient((request) async {
          requests.add(request);
          final key = '${request.method} ${request.url.path}';
          final answer = answers[key];
          if (answer == null) {
            return http.Response('{"detail":"no route $key"}', 404);
          }
          return http.Response(
            jsonEncode(answer.body),
            answer.status,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

  Map<String, dynamic> bodyOf(int i) =>
      jsonDecode(requests[i].body) as Map<String, dynamic>;
}

const _conversation = {
  'id': 4,
  'status': 'open',
  'topic': 'trains',
  'input_mode': 'speech',
  'transcript_allowed': false,
  'turns_used': 0,
  'turns_left': 8,
  'end_reason': null,
  'started_at': '2026-10-01T09:00:00',
  'ended_at': null,
  'providers': {'reply': 'fake', 'speech': 'fake', 'avatar': 'fake'},
};
const _limits = {
  'max_turns': 8,
  'max_minutes': 8,
  'max_reply_words': 40,
  'max_participant_chars': 400,
  'input_modes': ['typed', 'speech'],
};

void main() {
  test('snapshot: GET /me/sessions/{sid}/live', () async {
    final w = Wire();
    w.answers['GET /me/sessions/11/live'] = (
      status: 200,
      body: {
        'conversation': null,
        'turns': const [],
        'limits': _limits,
        'store_transcript_offered': true,
        'input_modes': ['typed', 'speech'],
      },
    );
    final s = await ApiLiveRepository(w.client()).snapshot('11');
    expect(w.requests.single.headers['Authorization'], 'Bearer tok');
    expect(s.conversation, isNull);
    expect(s.storeTranscriptOffered, isTrue);
    expect(s.offersSpeech, isTrue);
    expect(s.limits.maxParticipantChars, 400);
  });

  test('start: the choices are sent, the video address is resolved against '
      'the service, the face layout and resumed flag are read', () async {
    final w = Wire();
    w.answers['POST /me/sessions/11/live/start'] = (
      status: 200,
      body: {
        'conversation': _conversation,
        'turns': [
          {'index': 0, 'role': 'avatar', 'text': 'Hi Sam!', 'chars': 7, 'flags': ['opening']},
        ],
        'avatar': {
          'mode': 'sample_video',
          'video_url': '/static/live/sample-face.webm',
          'voice': 'browser_tts',
          'captions': true,
          'synthetic': true,
          'note': 'Development avatar',
        },
        'face_layout': {
          'face_box': [0.3, 0.1, 0.4, 0.8],
          'eye_region': [0.3, 0.25, 0.4, 0.2],
          'mouth_region': [0.3, 0.55, 0.4, 0.25],
        },
        'limits': _limits,
        'resumed': false,
      },
    );
    final s = await ApiLiveRepository(w.client()).start(
      '11',
      mode: LiveInputMode.speech,
      allowTranscript: true,
      tMs: 1234,
    );
    expect(w.bodyOf(0), {
      'input_mode': 'speech',
      'allow_transcript': true,
      't_ms': 1234,
    });
    expect(s.avatar.videoUrl, 'http://api.test:8000/static/live/sample-face.webm');
    expect(s.avatar.synthetic, isTrue);
    expect(s.turns.single.text, 'Hi Sam!');
    expect(s.faceLayout!.faceBox, const Box(0.3, 0.1, 0.4, 0.8));
    expect(s.resumed, isFalse);
    expect(s.conversation.inputMode, LiveInputMode.speech);
  });

  test('start without t_ms leaves it out; an absolute video address stays '
      'as it is', () async {
    final w = Wire();
    w.answers['POST /me/sessions/11/live/start'] = (
      status: 200,
      body: {
        'conversation': _conversation,
        'turns': const [],
        'avatar': {'video_url': 'https://cdn.example/face.webm', 'synthetic': false},
        'face_layout': null,
        'limits': _limits,
        'resumed': true,
      },
    );
    final s = await ApiLiveRepository(w.client())
        .start('11', mode: LiveInputMode.typed, allowTranscript: false);
    expect(w.bodyOf(0), {'input_mode': 'typed', 'allow_transcript': false});
    expect(s.avatar.videoUrl, 'https://cdn.example/face.webm');
    expect(s.faceLayout, isNull);
    expect(s.resumed, isTrue);
  });

  test('a typed turn sends expect_turn and the text; the answer is read',
      () async {
    final w = Wire();
    w.answers['POST /me/sessions/11/live/turn'] = (
      status: 200,
      body: {
        'participant': {'index': 1, 'role': 'participant', 'text': 'hello', 'chars': 5, 'flags': ['typed']},
        'avatar': {'index': 2, 'role': 'avatar', 'text': 'Hi again', 'chars': 8, 'flags': [], 'latency_ms': 12},
        'turns_used': 1,
        'turns_left': 7,
        'done': false,
        'end_reason': null,
        'distress': true,
      },
    );
    final r = await ApiLiveRepository(w.client())
        .sendTurn('11', expectTurn: 0, text: 'hello', tMs: 900);
    expect(w.bodyOf(0), {'expect_turn': 0, 'text': 'hello', 't_ms': 900});
    expect(r.avatar.text, 'Hi again');
    expect(r.turnsUsed, 1);
    expect(r.distress, isTrue);
    expect(r.done, isFalse);
  });

  test('a spoken turn is a multipart upload: expect_turn and t_ms before the '
      'file, the media type without parameters', () async {
    final w = Wire();
    w.answers['POST /me/sessions/11/live/turn-audio'] = (
      status: 200,
      body: {
        'participant': {'index': 1, 'role': 'participant', 'text': 'I like trains', 'chars': 13, 'flags': ['speech']},
        'avatar': {'index': 2, 'role': 'avatar', 'text': 'Nice!', 'chars': 5, 'flags': []},
        'turns_used': 1,
        'turns_left': 7,
        'done': false,
        'end_reason': null,
        'distress': false,
      },
    );
    final clip = AudioClip(
      bytes: Uint8List.fromList(List.generate(300, (i) => i % 251)),
      contentType: 'audio/webm;codecs=opus',
    );
    final r = await ApiLiveRepository(w.client())
        .sendAudio('11', expectTurn: 0, clip: clip, tMs: 4000);
    final req = w.requests.single;
    expect(req.method, 'POST');
    expect(req.headers['Authorization'], 'Bearer tok');
    expect(req.headers['Content-Type'], startsWith('multipart/form-data; boundary='));
    final body = latin1.decode(req.bodyBytes);
    expect(body, contains('name="expect_turn"\r\n\r\n0\r\n'));
    expect(body, contains('name="t_ms"\r\n\r\n4000\r\n'));
    expect(body, contains('name="file"; filename="speech.webm"'));
    expect(body, contains('Content-Type: audio/webm\r\n'));
    expect(body.indexOf('name="expect_turn"'),
        lessThan(body.indexOf('name="file"')),
        reason: 'text fields come before the file');
    expect(req.bodyBytes.length, greaterThan(300));
    expect(r.participant!.text, 'I like trains');
  });

  test('end: POST .../live/end with t_ms', () async {
    final w = Wire();
    w.answers['POST /me/sessions/11/live/end'] = (
      status: 200,
      body: {
        'avatar': {'index': 3, 'role': 'avatar', 'text': 'Bye', 'chars': 3, 'flags': ['closing']},
        'turns_used': 2,
        'done': true,
        'end_reason': 'participant_ended',
      },
    );
    final r = await ApiLiveRepository(w.client()).end('11', tMs: 55);
    expect(w.bodyOf(0), {'t_ms': 55});
    expect(r.done, isTrue);
    expect(r.endReason, 'participant_ended');
    expect(r.avatar.text, 'Bye');
  });

  test('a 409 and a 422 keep the server text and status', () async {
    final w = Wire();
    w.answers['POST /me/sessions/11/live/turn'] = (
      status: 409,
      body: {'detail': 'this turn was already sent; reload the conversation'},
    );
    final repo = ApiLiveRepository(w.client());
    await expectLater(
      repo.sendTurn('11', expectTurn: 0, text: 'x'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'status', 409)
          .having((e) => e.message, 'message',
              'this turn was already sent; reload the conversation')),
    );
    w.answers['POST /me/sessions/11/live/turn-audio'] = (
      status: 422,
      body: {
        'detail': 'we could not turn that into text (empty); please try again or type',
      },
    );
    await expectLater(
      repo.sendAudio(
        '11',
        expectTurn: 0,
        clip: AudioClip(bytes: Uint8List(8), contentType: 'audio/webm'),
      ),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'status', 422)
          .having((e) => e.message, 'message', startsWith('we could not turn'))),
    );
  });
}
