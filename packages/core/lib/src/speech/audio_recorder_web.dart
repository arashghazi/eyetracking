// Web-only microphone recording. Loaded through a conditional import, so it
// is never compiled for the VM or Android.
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'audio_recorder.dart';

/// Records the microphone with `getUserMedia` (audio only) and
/// `MediaRecorder`: `audio/webm;codecs=opus` when the browser can, otherwise
/// the browser's own default type. Stops by itself after [maxDuration], and
/// stops every microphone track when a clip ends.
class WebAudioRecorder implements AudioRecorder {
  WebAudioRecorder({this.maxDuration = const Duration(seconds: 30)});

  /// The type asked for first.
  static const preferredType = 'audio/webm;codecs=opus';

  @override
  final Duration maxDuration;

  web.MediaStream? _stream;
  web.MediaRecorder? _recorder;
  final List<web.Blob> _chunks = [];
  Completer<AudioClip?>? _done;
  Timer? _limit;
  DateTime? _startedAt;
  bool _starting = false;
  bool _cancelled = false;

  @override
  bool get isSupported {
    try {
      return web.window.has('MediaRecorder') &&
          web.window.navigator.has('mediaDevices');
    } catch (_) {
      return false;
    }
  }

  @override
  bool get isRecording => _recorder?.state == 'recording';

  @override
  Future<void> start({void Function()? onLimit}) async {
    if (_starting || isRecording) return;
    if (!isSupported) {
      throw const AudioRecorderException(
          'Recording is not available in this browser. Please type instead.');
    }
    _starting = true;
    _cancelled = false;
    _chunks.clear();
    final done = Completer<AudioClip?>();
    _done = done;
    try {
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(
            audio: true.toJS,
            video: false.toJS,
          ))
          .toDart;
      _stream = stream;
      if (_cancelled) {
        // Let go (or cancelled) while the permission prompt was open.
        _release();
        _done = null;
        done.complete(null);
        return;
      }
      final recorder = web.MediaRecorder.isTypeSupported(preferredType)
          ? web.MediaRecorder(
              stream, web.MediaRecorderOptions(mimeType: preferredType))
          : web.MediaRecorder(stream);
      _recorder = recorder;
      recorder.ondataavailable = ((web.BlobEvent event) {
        if (event.data.size > 0) _chunks.add(event.data);
      }).toJS;
      recorder.onstop = ((web.Event _) => unawaited(_finish(recorder))).toJS;
      recorder.onerror = ((web.Event _) {
        _cancelled = true;
        if (recorder.state != 'inactive') recorder.stop();
      }).toJS;
      recorder.start();
      _startedAt = DateTime.now();
      _limit = Timer(maxDuration, () {
        if (!isRecording) return;
        recorder.stop();
        onLimit?.call();
      });
    } catch (e) {
      _release();
      _done = null;
      if (!done.isCompleted) done.complete(null);
      throw AudioRecorderException(_message(e));
    } finally {
      _starting = false;
    }
  }

  @override
  Future<AudioClip?> stop() async {
    final done = _done;
    if (done == null) return null;
    if (_starting) {
      // Not recording yet (the microphone is still being asked for): there
      // is nothing to return, and nothing may start afterwards.
      _cancelled = true;
      return done.future;
    }
    final recorder = _recorder;
    if (recorder != null && recorder.state != 'inactive') recorder.stop();
    return done.future;
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    final recorder = _recorder;
    if (recorder != null && recorder.state != 'inactive') {
      recorder.stop();
      await _done?.future;
    } else {
      _release();
      final done = _done;
      if (done != null && !done.isCompleted) done.complete(null);
    }
  }

  /// The recorder stopped: build the clip, give the microphone back.
  Future<void> _finish(web.MediaRecorder recorder) async {
    final done = _done;
    final started = _startedAt;
    final type = recorder.mimeType.isEmpty ? preferredType : recorder.mimeType;
    final chunks = List<web.Blob>.of(_chunks);
    final cancelled = _cancelled;
    _release();
    if (done == null || done.isCompleted) return;
    if (cancelled || chunks.isEmpty) {
      done.complete(null);
      return;
    }
    try {
      final blob = web.Blob(
        chunks.toJS,
        web.BlobPropertyBag(type: type),
      );
      final buffer = await blob.arrayBuffer().toDart;
      final bytes = Uint8List.view(buffer.toDart);
      done.complete(AudioClip(
        bytes: bytes,
        contentType: type,
        duration: started == null
            ? Duration.zero
            : DateTime.now().difference(started),
      ));
    } catch (_) {
      done.complete(null);
    }
  }

  /// Stops the timer and every microphone track.
  void _release() {
    _limit?.cancel();
    _limit = null;
    final stream = _stream;
    _stream = null;
    _recorder = null;
    if (stream != null) {
      for (final track in stream.getTracks().toDart) {
        track.stop();
      }
    }
  }

  String _message(Object e) {
    final text = e.toString();
    if (text.contains('NotAllowed') || text.contains('Permission')) {
      return 'Microphone access was not allowed. Allow it for this page in '
          'the browser address bar, or type instead.';
    }
    if (text.contains('NotFound') || text.contains('Devices not found')) {
      return 'No microphone was found. Connect one, or type instead.';
    }
    if (text.contains('NotReadable') || text.contains('TrackStart')) {
      return 'The microphone is being used by another program. Close it, or '
          'type instead.';
    }
    if (text.contains('SecurityError')) {
      return 'The browser blocked the microphone on this address. Use https '
          'or localhost, or type instead.';
    }
    return 'The microphone could not be started. Check it, or type instead.';
  }
}

AudioRecorder createAudioRecorder({
  Duration maxDuration = const Duration(seconds: 30),
}) =>
    WebAudioRecorder(maxDuration: maxDuration);
