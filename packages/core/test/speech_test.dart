import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:eyetracking_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('speech stub (outside the browser)', () {
    test('is unavailable and every call is a harmless no-op', () {
      final synth = createSpeechSynthesizer();
      expect(synth.isAvailable, isFalse);
      synth.speak('Hello there');
      synth.cancel();
    });
  });

  group('recorder stub (outside the browser)', () {
    test('is not supported and starting says to type instead', () async {
      final recorder = createAudioRecorder();
      expect(recorder.isSupported, isFalse);
      expect(recorder.isRecording, isFalse);
      expect(recorder.maxDuration, const Duration(seconds: 30));
      await expectLater(
        recorder.start(),
        throwsA(isA<AudioRecorderException>()
            .having((e) => e.message, 'message', contains('type instead'))),
      );
      expect(await recorder.stop(), isNull);
      await recorder.cancel();
    });

    test('keeps the limit it was made with', () {
      final recorder = createAudioRecorder(maxDuration: const Duration(seconds: 5));
      expect(recorder.maxDuration, const Duration(seconds: 5));
    });
  });

  group('AudioClip', () {
    test('reports the media type without parameters and a matching name', () {
      AudioClip clip(String type) =>
          AudioClip(bytes: Uint8List(1), contentType: type);
      expect(clip('audio/webm;codecs=opus').mediaType, 'audio/webm');
      expect(clip('audio/webm;codecs=opus').filename, 'speech.webm');
      expect(clip('Audio/OGG; codecs=opus').mediaType, 'audio/ogg');
      expect(clip('audio/ogg').filename, 'speech.ogg');
      expect(clip('audio/mp4').filename, 'speech.mp4');
      expect(clip('audio/wav').filename, 'speech.wav');
      expect(clip('audio/mpeg').filename, 'speech.mp3');
      expect(clip('').filename, 'speech.webm');
    });
  });

  group('FakeSpeechSynthesizer', () {
    test('records every spoken line and every cancel', () {
      final synth = FakeSpeechSynthesizer();
      expect(synth.isAvailable, isTrue);
      synth.speak('One');
      synth.speak('Two');
      synth.cancel();
      expect(synth.spoken, ['One', 'Two']);
      expect(synth.cancelCount, 1);
    });

    test('says nothing when it is unavailable', () {
      final synth = FakeSpeechSynthesizer(available: false);
      synth.speak('Hidden');
      expect(synth.isAvailable, isFalse);
      expect(synth.spoken, isEmpty);
    });
  });

  group('FakeAudioRecorder', () {
    test('records one clip: start, stop, bytes and type', () async {
      final recorder = FakeAudioRecorder();
      expect(recorder.isRecording, isFalse);
      await recorder.start();
      expect(recorder.isRecording, isTrue);
      final clip = await recorder.stop();
      expect(recorder.isRecording, isFalse);
      expect(clip!.bytes, [1, 2, 3, 4]);
      expect(clip.contentType, 'audio/webm;codecs=opus');
      expect(recorder.startCount, 1);
      expect(recorder.stopCount, 1);
      expect(await recorder.stop(), isNull);
    });

    test('hitting the limit stops by itself, then stop still gives the clip',
        () async {
      final recorder = FakeAudioRecorder();
      var limit = 0;
      await recorder.start(onLimit: () => limit++);
      recorder.hitLimit();
      expect(limit, 1);
      expect(recorder.isRecording, isFalse);
      expect((await recorder.stop())!.bytes, isNotEmpty);
    });

    test('cancel throws the clip away; a blocked microphone throws', () async {
      final recorder = FakeAudioRecorder();
      await recorder.start();
      await recorder.cancel();
      expect(recorder.cancelCount, 1);
      expect(await recorder.stop(), isNull);
      recorder.startError = const AudioRecorderException('blocked');
      await expectLater(recorder.start(), throwsA(isA<AudioRecorderException>()));
    });

    test('recording nothing returns no clip', () async {
      final recorder = FakeAudioRecorder()..recordNothing = true;
      await recorder.start();
      expect(await recorder.stop(), isNull);
    });
  });
}
