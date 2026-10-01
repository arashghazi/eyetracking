import 'dart:async';
import 'dart:typed_data';

import 'audio_recorder.dart';

/// A scripted recorder for tests: no microphone, a clip made of [bytes].
/// Import through `testing.dart`.
class FakeAudioRecorder implements AudioRecorder {
  FakeAudioRecorder({
    this.supported = true,
    this.maxDuration = const Duration(seconds: 30),
    Uint8List? bytes,
    this.contentType = 'audio/webm;codecs=opus',
    this.clipDuration = const Duration(seconds: 2),
  }) : bytes = bytes ?? Uint8List.fromList(const [1, 2, 3, 4]);

  bool supported;
  @override
  final Duration maxDuration;
  Uint8List bytes;
  String contentType;
  Duration clipDuration;

  /// When set, [start] throws it (a blocked microphone).
  AudioRecorderException? startError;

  /// When set, [start] waits for it (a permission prompt that is open).
  Completer<void>? startGate;

  /// When true, [stop] returns null (nothing was heard).
  bool recordNothing = false;

  int startCount = 0;
  int stopCount = 0;
  int cancelCount = 0;
  bool _recording = false;
  bool _limitHit = false;
  void Function()? _onLimit;

  @override
  bool get isSupported => supported;

  @override
  bool get isRecording => _recording;

  @override
  Future<void> start({void Function()? onLimit}) async {
    if (startError != null) throw startError!;
    startCount++;
    _onLimit = onLimit;
    _limitHit = false;
    final gate = startGate;
    if (gate != null) await gate.future;
    _recording = true;
  }

  /// Pretends [maxDuration] passed: the recorder stops itself and tells the
  /// caller, who then collects the clip with [stop].
  void hitLimit() {
    if (!_recording) return;
    _recording = false;
    _limitHit = true;
    _onLimit?.call();
  }

  @override
  Future<AudioClip?> stop() async {
    if (!_recording && !_limitHit) return null;
    stopCount++;
    _recording = false;
    _limitHit = false;
    if (recordNothing) return null;
    return AudioClip(
      bytes: bytes,
      contentType: contentType,
      duration: clipDuration,
    );
  }

  @override
  Future<void> cancel() async {
    if (_recording || _limitHit) cancelCount++;
    _recording = false;
    _limitHit = false;
  }
}
