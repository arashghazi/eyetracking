import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:participant_app/features/session/application/interest_practice_controller.dart';
import 'package:participant_app/features/session/domain/media_key.dart';

import 'practice_kit.dart';
import 'session_kit.dart';

List<RecordedEvent> mediaStarts(InterestRig rig) => [
      for (final e in rig.repo.events)
        if (e.type == SessionEventType.mediaStart) e,
    ];

void main() {
  group('the media key of a signed link', () {
    test('is the last path part before the token', () {
      expect(mediaKeyFromUrl('/media/s1.webm/abc.def', 's1'), 's1.webm');
      expect(mediaKeyFromUrl('http://api.test/media/clips/s2.mp4/tok', 's2'), 's2.mp4');
      expect(mediaKeyFromUrl('http://api.test/media/s3.webm?token=abc&x=1', 's3'), 's3.webm');
      expect(mediaKeyFromUrl('/media/s%201.webm/tok', 's1'), 's 1.webm',
          reason: 'the percent-encoding of the path is undone');
    });

    test('is the segment id when the link does not carry the key', () {
      // The service issues /media/<token>: the key is inside the token.
      expect(mediaKeyFromUrl('/media/abc.def-ghi', 's7'), 's7');
      expect(mediaKeyFromUrl('http://api.test:8000/media/abc.def-ghi', 's7'), 's7');
      expect(mediaKeyFromUrl('', 's7'), 's7');
      expect(mediaKeyFromUrl('/', 's7'), 's7');
      expect(mediaKeyFromUrl('http://[bad', 's7'), 's7');
      expect(mediaKeyFromUrl('https://cdn.test/media?sig=1', 's7'), 's7');
    });
  });

  group('media_start events', () {
    test('a clip that starts is announced with its segment and media key',
        () async {
      final rig = InterestRig(
        content: PersonalizedContent(
          startSegment: 's1',
          segments: const [
            PersonalizedSegment(
              id: 's1',
              mediaUrl: '/media/s1.webm/tok1',
              faceLayout: testFaceLayout,
            ),
          ],
        ),
      );
      final i = rig.controller;
      addTearDown(i.dispose);
      i.start();
      expect(mediaStarts(rig), isEmpty, reason: 'nothing before the picture moves');

      i.onVideoRect(const Box(0, 40, 1440, 860));
      i.onVideoPlaying();
      await settle();
      final e = mediaStarts(rig).single;
      expect(e.payload, {'segment_id': 's1', 'media_key': 's1.webm'});
      expect(e.tMs, greaterThan(0), reason: 'the session clock');
    });

    test('the segment id stands in when the link has no key', () async {
      final rig = InterestRig(); // links are /media/s1, /media/s2, ...
      final i = rig.controller;
      addTearDown(i.dispose);
      i.start();
      await rig.playCurrent();
      expect(mediaStarts(rig).single.payload, {'segment_id': 's1', 'media_key': 's1'});
    });

    test('the key the service names wins over the link', () async {
      final rig = InterestRig(
        content: PersonalizedContent(
          startSegment: 's1',
          segments: [
            PersonalizedSegment.fromJson({
              'id': 's1',
              'media_url': '/media/opaque-token',
              'media_key': 'intro.webm',
              'face_layout': {
                'face_box': [0.3, 0.1, 0.4, 0.8],
                'eye_region': [0.3, 0.25, 0.4, 0.2],
                'mouth_region': [0.3, 0.55, 0.4, 0.25],
              },
            }),
          ],
        ),
      );
      final i = rig.controller;
      addTearDown(i.dispose);
      i.start();
      await rig.playCurrent();
      expect(mediaStarts(rig).single.payload, {'segment_id': 's1', 'media_key': 'intro.webm'});
    });

    test('once per clip, even when the player reports playing again', () async {
      final rig = InterestRig();
      final i = rig.controller;
      addTearDown(i.dispose);
      i.start();
      i.onVideoRect(const Box(0, 40, 1440, 860));
      i.onVideoPlaying();
      i.onVideoPlaying(); // a stall and resume
      i.onVideoPlaying();
      await settle();
      expect(mediaStarts(rig), hasLength(1));
    });

    test('every clip of the conversation and the post clip is announced',
        () async {
      final rig = InterestRig();
      final i = rig.controller;
      addTearDown(i.dispose);
      i.start();
      await rig.playCurrent(); // s1
      await i.answerInteraction('Trains');
      await rig.playCurrent(); // s2
      await i.answerComprehension('Red');
      await i.answerComprehension('Rome');
      i.startPost();
      await rig.playCurrent(); // s3
      expect([for (final e in mediaStarts(rig)) e.payload!['segment_id']],
          ['s1', 's2', 's3']);
    });

    test('a clip played again after a device change is announced again',
        () async {
      final rig = InterestRig();
      final i = rig.controller;
      addTearDown(i.dispose);
      i.start();
      i.onVideoRect(const Box(0, 40, 1440, 860));
      i.onVideoPlaying();
      await settle();
      i.interrupted();
      i.restartCurrent();
      i.onVideoPlaying();
      await settle();
      expect(mediaStarts(rig), hasLength(2));
    });

    test('a failed announcement never stops the practice', () async {
      final rig = InterestRig();
      final i = rig.controller;
      addTearDown(i.dispose);
      rig.repo.eventFailure = const ApiException('The server took too long.');
      i.start();
      await rig.playCurrent();
      expect(i.phase, InterestPhase.question, reason: 'the practice went on');
      expect(i.error, isNull);
    });

    test('no announcement for a clip that is not ready', () async {
      final rig = InterestRig(
        content: PersonalizedContent(
          startSegment: 's1',
          segments: const [PersonalizedSegment(id: 's1', mediaUrl: '', faceLayout: testFaceLayout)],
        ),
      );
      final i = rig.controller;
      addTearDown(i.dispose);
      i.start();
      expect(i.videoProblem, 'The video is not ready');
      expect(mediaStarts(rig), isEmpty);
    });
  });
}
