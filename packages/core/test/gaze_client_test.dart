import 'dart:convert';
import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:eyetracking_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('GazeServiceClient', () {
    test('local mode posts to /estimate without a token', () async {
      late http.Request seen;
      final client = GazeServiceClient.local(
        baseUrl: 'http://gaze.test:8100',
        httpClient: MockClient((request) async {
          seen = request;
          return _json(200, {
            't_ms': 900,
            'face_detected': true,
            'face_box': [1, 2, 3, 4],
            'face_conf': 0.95,
            'yaw_deg': 3.0,
            'pitch_deg': -1.0,
            'gaze_conf': 0.6,
            'frame_w': 640,
            'frame_h': 480,
            'model_id': 'stub',
          });
        }),
      );

      final sample = await client.estimate(
        Uint8List.fromList([1, 2, 3]),
        900,
        640,
        480,
      );

      expect(seen.url.toString(), 'http://gaze.test:8100/estimate');
      expect(seen.headers.containsKey('Authorization'), isFalse);
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['image_b64'], base64Encode([1, 2, 3]));
      expect(body['t_ms'], 900);
      expect(body['frame_w'], 640);
      expect(body['frame_h'], 480);
      expect(sample.faceDetected, isTrue);
      expect(sample.modelId, 'stub');
      expect(sample.faceBox, const Box(1, 2, 3, 4));
    });

    test('info reads the model description', () async {
      final client = GazeServiceClient.local(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/info');
          return _json(200, {
            'model_id': 'stub-1',
            'model_version': '0.1',
            'synthetic': true,
            'face_detector': 'haar',
            'max_fps': 15,
          });
        }),
      );
      final info = await client.info();
      expect(info.synthetic, isTrue);
      expect(info.modelId, 'stub-1');
      expect(info.maxFps, 15);
    });

    test('server mode uses /gaze/* with the bearer token', () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        baseUrl: 'http://research.test:8000',
        tokenStore: TokenStore()..save('tok'),
        httpClient: MockClient((request) async {
          requests.add(request);
          return request.url.path.endsWith('/info')
              ? _json(200, {
                  'model_id': 'm',
                  'model_version': '1',
                  'synthetic': false,
                })
              : _json(200, {
                  't_ms': 5,
                  'face_detected': false,
                  'face_conf': 0,
                  'gaze_conf': 0,
                  'frame_w': 10,
                  'frame_h': 10,
                });
        }),
      );
      final client = GazeServiceClient.fromEnvironment(
        api,
        mode: GazeMode.server,
      );

      await client.info();
      await client.estimate(Uint8List(1), 5, 10, 10);

      expect(requests.map((r) => r.url.path), ['/gaze/info', '/gaze/estimate']);
      expect(requests.every((r) => r.headers['Authorization'] == 'Bearer tok'),
          isTrue);
    });

    test('an unreachable service gets a gaze-specific message', () async {
      final client = GazeServiceClient.local(
        httpClient: MockClient((request) async => throw http.ClientException('x')),
      );
      await expectLater(
        client.info(),
        throwsA(isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('gaze service'),
        )),
      );
    });

    test('service errors keep their detail', () async {
      final client = GazeServiceClient.local(
        httpClient: MockClient(
          (request) async => _json(422, {'detail': 'image is not a JPEG'}),
        ),
      );
      await expectLater(
        client.estimate(Uint8List(1), 1, 1, 1),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'image is not a JPEG')),
      );
    });
  });

  group('test doubles', () {
    test('FakeFrameSource generates frames on the shared clock', () async {
      final source = FakeFrameSource(interval: const Duration(milliseconds: 2));
      await source.start();
      source.restartClock();
      final frames = await source.frames().take(3).toList();
      expect(frames, hasLength(3));
      expect(frames.first.tMs, lessThanOrEqualTo(frames.last.tMs));
      expect(source.streaming, isFalse);
      expect(source.startCount, 1);
    });

    test('FakeFrameSource emits camera changes', () async {
      final source = FakeFrameSource();
      final seen = <FrameSourceEvent>[];
      source.events.listen(seen.add);
      source.emitEvent(FrameSourceEvent.orientationChanged);
      expect(seen, [FrameSourceEvent.orientationChanged]);
    });

    test('the non-web stub reports that capture is unavailable', () async {
      expect(
        () => WebFrameSource().start(),
        throwsA(isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          'Camera capture is available on PC web first; Android arrives later',
        )),
      );
    });

    test('FakeGazeEstimator reports no face when asked', () async {
      final gaze = FakeGazeEstimator()..facePresent = false;
      final s = await gaze.estimate(Uint8List(1), 10, 640, 480);
      expect(s.faceDetected, isFalse);
      expect(gaze.estimateCalls, 1);
    });
  });
}
