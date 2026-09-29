import 'dart:convert';
import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:research_admin/features/assignments/data/api_assignments_repository.dart';
import 'package:research_admin/features/content/data/api_content_repository.dart';
import 'package:research_admin/features/protocols/data/api_protocols_repository.dart';

import 'fakes.dart';

/// The wire of the step 3 researcher endpoints, against a canned HTTP client.
class Recorder {
  final List<http.BaseRequest> requests = [];
  final List<String> bodies = [];
  final Map<String, Object> answers = {};

  ApiClient client() => ApiClient(
        baseUrl: 'http://api.test:8000',
        tokenStore: TokenStore()..save('tok'),
        httpClient: MockClient.streaming((request, body) async {
          requests.add(request);
          bodies.add(latin1.decode(await body.expand((c) => c).toList()));
          final key = '${request.method} ${request.url.path}';
          final answer = answers[key];
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode(answer ?? {'detail': 'no route $key'}))),
            answer == null ? 404 : 200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

  Map<String, dynamic> bodyOf(int i) => jsonDecode(bodies[i]) as Map<String, dynamic>;
}

void main() {
  group('protocols', () {
    final def = ProtocolDefinition.starter(ProtocolPath.gradualFace);

    test('list, create, update and get', () async {
      final r = Recorder();
      r.answers['GET /studies/1/protocols'] = [
        {'id': 4, 'name': 'Faces', 'version': 1, 'status': 'published', 'path': 'gradual_face',
         'created_at': '2026-09-29T08:00:00', 'published_at': '2026-09-30T08:00:00'},
      ];
      r.answers['POST /studies/1/protocols'] = {
        'id': 9, 'name': 'New', 'version': 0, 'status': 'draft', 'path': 'gradual_face',
        'definition': def.toJson(),
      };
      r.answers['PUT /studies/1/protocols/9'] = {
        'id': 9, 'name': 'Renamed', 'version': 0, 'status': 'draft', 'path': 'gradual_face',
        'definition': def.toJson(),
      };
      final repo = ApiProtocolsRepository(r.client());

      final list = await repo.list(1);
      expect(list.single.isPublished, isTrue);
      expect(r.requests.first.headers['Authorization'], 'Bearer tok');

      final created = await repo.create(1, 'New', def);
      expect(r.bodyOf(1)['name'], 'New');
      expect((r.bodyOf(1)['definition'] as Map)['path'], 'gradual_face');
      expect(created.summary.id, '9');
      expect(created.definition.gradual!.stages, isNotEmpty);

      final updated = await repo.update(1, '9', name: 'Renamed', definition: def);
      expect(updated.summary.name, 'Renamed');
      expect(r.bodyOf(2).keys, unorderedEquals(['name', 'definition']));
      await repo.update(1, '9', name: 'Only name');
      expect(r.bodyOf(3), {'name': 'Only name'});
    });

    test('publish and new draft ask again for the definition when the answer '
        'has none', () async {
      final r = Recorder();
      r.answers['POST /studies/1/protocols/9/publish'] = {
        'id': 9, 'name': 'New', 'version': 3, 'status': 'published', 'path': 'gradual_face',
      };
      r.answers['GET /studies/1/protocols/9'] = {
        'id': 9, 'name': 'New', 'version': 3, 'status': 'published', 'path': 'gradual_face',
        'definition': def.toJson(),
      };
      r.answers['POST /studies/1/protocols/9/new-draft'] = {
        'id': 12, 'name': 'New', 'version': 0, 'status': 'draft', 'path': 'gradual_face',
        'definition': def.toJson(),
      };
      final repo = ApiProtocolsRepository(r.client());
      final published = await repo.publish(1, '9');
      expect(published.summary.version, 3);
      expect(published.definition.gradual, isNotNull, reason: 'read again, not guessed');
      expect(r.requests.map((q) => '${q.method} ${q.url.path}'), [
        'POST /studies/1/protocols/9/publish',
        'GET /studies/1/protocols/9',
      ]);
      final draft = await repo.newDraft(1, '9');
      expect(draft.summary.id, '12');
      expect(draft.summary.isDraft, isTrue);
      expect(r.requests.length, 3, reason: 'the copy came with its definition');
    });

    test('a 422 keeps the server sentence', () async {
      final r = Recorder();
      expect(
        () => ApiProtocolsRepository(r.client()).publish(1, '404'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'no route POST /studies/1/protocols/404/publish')),
      );
    });
  });

  group('content', () {
    test('create and update send the whole item; approve; media', () async {
      final r = Recorder();
      final detail = {
        'id': 7, 'title': 'Trains', 'topic_tags': ['trains'], 'face_id': 'f1', 'voice_id': 'v1',
        'status': 'draft', 'media_keys': ['s1.webm'], 'missing_media': ['s1.webm'],
        'definition': sampleContentDefinition().toJson(),
      };
      r.answers['POST /studies/2/content'] = detail;
      r.answers['PUT /studies/2/content/7'] = detail;
      r.answers['POST /studies/2/content/7/approve'] = {...detail, 'status': 'approved', 'missing_media': []};
      r.answers['GET /studies/2/content'] = [
        {...detail}..remove('definition'),
      ];
      r.answers['GET /studies/2/content/7/media'] = [
        {'key': 's1.webm', 'content_type': 'video/webm', 'size': 10, 'url': '/media/x'},
      ];
      final repo = ApiContentRepository(r.client());

      final created = await repo.create(
        2,
        title: 'Trains',
        topicTags: ['trains'],
        faceId: 'f1',
        voiceId: 'v1',
        definition: sampleContentDefinition(),
      );
      expect(r.bodyOf(0)['title'], 'Trains');
      expect(r.bodyOf(0)['topic_tags'], ['trains']);
      expect(r.bodyOf(0)['face_id'], 'f1');
      expect((r.bodyOf(0)['definition'] as Map)['start_segment'], 's1');
      expect(created.summary.missingMedia, ['s1.webm']);
      expect(created.definition.segments, hasLength(2));

      await repo.update(2, '7',
          title: 'Trains 2', topicTags: const [], faceId: '', voiceId: '',
          definition: sampleContentDefinition());
      expect(r.bodyOf(1)['title'], 'Trains 2');

      final approved = await repo.approve(2, '7');
      expect(approved.summary.isApproved, isTrue);

      final list = await repo.list(2);
      expect(list.single.missingMedia, ['s1.webm']);
      final media = await repo.media(2, '7');
      expect(media.single.size, 10);
    });

    test('the upload goes to the key path as multipart with the token',
        () async {
      final r = Recorder();
      r.answers['POST /studies/2/content/7/media/s1.webm'] = {
        'key': 's1.webm', 'content_type': 'video/webm', 'size': 6,
      };
      final progress = <int>[];
      final info = await ApiContentRepository(r.client()).uploadMedia(
        2,
        '7',
        's1.webm',
        bytes: Uint8List.fromList([1, 2, 3, 4, 5, 6]),
        filename: 's1.webm',
        contentType: 'video/webm',
        onProgress: (sent, total) => progress.add(sent),
      );
      expect(info.key, 's1.webm');
      expect(info.size, 6);
      final request = r.requests.single;
      expect(request.headers['Authorization'], 'Bearer tok');
      expect(request.headers['Content-Type'], startsWith('multipart/form-data'));
      expect(r.bodies.single, contains('name="file"; filename="s1.webm"'));
      expect(progress, isNotEmpty);
    });
  });

  group('assignments', () {
    final row = {
      'id': 50, 'order_index': 1, 'status': 'ready',
      'protocol': {'id': 3, 'name': 'Talk', 'version': 1, 'path': 'interest_conversation'},
      'topic': 'trains', 'topic_free_text': null, 'content_id': 7, 'content_title': 'Trains',
    };

    test('list, assign, attach and cancel use numeric ids', () async {
      final r = Recorder();
      r.answers['GET /studies/1/participants/P-001/assignments'] = [row];
      r.answers['POST /studies/1/participants/P-001/assignments'] = row;
      r.answers['PUT /studies/1/participants/P-001/assignments/50'] = row;
      final repo = ApiAssignmentsRepository(r.client());

      final list = await repo.list(1, 'P-001');
      expect(list.single.contentTitle, 'Trains');

      await repo.create(1, 'P-001', protocolId: '3', orderIndex: 2);
      expect(r.bodyOf(1), {'protocol_id': 3, 'order_index': 2});
      await repo.create(1, 'P-001', protocolId: '3');
      expect(r.bodyOf(2), {'protocol_id': 3}, reason: 'the server appends');

      await repo.attachContent(1, 'P-001', '50', '7');
      expect(r.bodyOf(3), {'content_id': 7});
      await repo.cancel(1, 'P-001', '50');
      expect(r.bodyOf(4), {'status': 'cancelled'});
    });

    test('the participant code is encoded in the path', () async {
      final r = Recorder();
      r.answers['GET /studies/1/participants/P%20001/assignments'] = [];
      await ApiAssignmentsRepository(r.client()).list(1, 'P 001');
      expect(r.requests.single.url.path, '/studies/1/participants/P%20001/assignments');
    });
  });
}
