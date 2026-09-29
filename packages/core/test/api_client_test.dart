import 'dart:convert';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('ApiClient requests', () {
    test('sends the bearer token and decodes JSON', () async {
      late http.BaseRequest seen;
      final tokens = TokenStore()..save('abc123');
      final api = ApiClient(
        baseUrl: 'http://api.test/',
        tokenStore: tokens,
        httpClient: MockClient((request) async {
          seen = request;
          return json(200, {'ok': true});
        }),
      );

      final result = await api.getObject('/me');

      expect(result, {'ok': true});
      expect(seen.method, 'GET');
      expect(seen.url.toString(), 'http://api.test/me');
      expect(seen.headers['Authorization'], 'Bearer abc123');
    });

    test('sends no Authorization header before sign-in', () async {
      late http.BaseRequest seen;
      final api = ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient((request) async {
          seen = request;
          return json(200, {'access_token': 't'});
        }),
      );
      await api.postObject('/auth/login', {'email': 'a@b.c', 'password': 'x'});
      expect(seen.headers.containsKey('Authorization'), isFalse);
    });

    test('POST and PUT send a JSON body', () async {
      final bodies = <String>[];
      final methods = <String>[];
      final api = ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient((request) async {
          methods.add(request.method);
          bodies.add(request.body);
          expect(request.headers['Content-Type'], contains('application/json'));
          return json(200, {'done': true});
        }),
      );
      await api.postObject('/x', {'a': 1});
      await api.putObject('/y', {'b': 'two'});
      expect(methods, ['POST', 'PUT']);
      expect(jsonDecode(bodies[0]), {'a': 1});
      expect(jsonDecode(bodies[1]), {'b': 'two'});
    });

    test('nullOn404 turns a missing resource into null', () async {
      final api = ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient((_) async => json(404, {'detail': 'none'})),
      );
      expect(await api.getObjectOrNull('/me/information-sheet'), isNull);
      expect(
        () => api.getObject('/me/information-sheet'),
        throwsA(isA<ApiException>().having((e) => e.isNotFound, 'isNotFound', true)),
      );
    });
  });

  group('ApiClient errors', () {
    ApiClient failing(http.Response response, {void Function()? onUnauthorized, TokenStore? tokens}) =>
        ApiClient(
          baseUrl: 'http://api.test',
          tokenStore: tokens,
          onUnauthorized: onUnauthorized,
          httpClient: MockClient((_) async => response),
        );

    test('uses the server detail as the message', () async {
      final api = failing(json(409, {'detail': 'email already registered'}));
      await expectLater(
        api.postObject('/users', {}),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'email already registered')
            .having((e) => e.statusCode, 'statusCode', 409)),
      );
    });

    test('joins FastAPI validation errors', () async {
      final api = failing(json(422, {
        'detail': [
          {'loc': ['body', 'password'], 'msg': 'too short', 'type': 'x'},
          {'loc': ['body'], 'msg': 'field required', 'type': 'y'},
        ],
      }));
      await expectLater(
        api.postObject('/users', {}),
        throwsA(isA<ApiException>().having(
          (e) => e.message,
          'message',
          'password: too short; field required',
        )),
      );
    });

    test('falls back to a generic sentence for non-JSON errors', () async {
      final api = failing(http.Response('<html>oops</html>', 500));
      await expectLater(
        api.getObject('/x'),
        throwsA(isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('error 500'),
        )),
      );
    });

    test('reports network failures without a status code', () async {
      final api = ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient((_) async => throw http.ClientException('down')),
      );
      await expectLater(
        api.getObject('/x'),
        throwsA(isA<ApiException>()
            .having((e) => e.isNetworkError, 'isNetworkError', true)
            .having((e) => e.message, 'message', contains('Could not reach'))),
      );
    });

    test('401 with a token signals an expired session', () async {
      var expired = 0;
      final api = failing(
        json(401, {'detail': 'invalid token'}),
        onUnauthorized: () => expired++,
        tokens: TokenStore()..save('old'),
      );
      await expectLater(api.getObject('/me'), throwsA(isA<ApiException>()));
      expect(expired, 1);
    });

    test('401 without a token (failed sign-in) does not', () async {
      var expired = 0;
      final api = failing(
        json(401, {'detail': 'invalid email or password'}),
        onUnauthorized: () => expired++,
      );
      await expectLater(
        api.postObject('/auth/login', {}),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'invalid email or password')),
      );
      expect(expired, 0);
    });

    test('a non-object body where an object is expected is an error', () async {
      final api = failing(json(200, [1, 2]));
      await expectLater(api.getObject('/x'), throwsA(isA<ApiException>()));
    });
  });

  test('TokenStore keeps the token in memory only', () {
    final store = TokenStore();
    expect(store.hasToken, isFalse);
    store.save('t');
    expect(store.token, 't');
    store.clear();
    expect(store.token, isNull);
  });
}
