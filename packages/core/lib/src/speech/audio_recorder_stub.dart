import 'audio_recorder.dart';

/// Outside the browser nothing can be recorded yet.
class StubAudioRecorder implements AudioRecorder {
  StubAudioRecorder({this.maxDuration = const Duration(seconds: 30)});

  @override
  final Duration maxDuration;

  @override
  bool get isSupported => false;

  @override
  bool get isRecording => false;

  @override
  Future<void> start({void Function()? onLimit}) async =>
      throw const AudioRecorderException(
          'Recording is available in the web app. Please type instead.');

  @override
  Future<AudioClip?> stop() async => null;

  @override
  Future<void> cancel() async {}
}

AudioRecorder createAudioRecorder({
  Duration maxDuration = const Duration(seconds: 30),
}) =>
    StubAudioRecorder(maxDuration: maxDuration);
