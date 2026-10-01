import 'dart:typed_data';

/// One finished recording.
class AudioClip {
  const AudioClip({
    required this.bytes,
    required this.contentType,
    this.duration = Duration.zero,
  });

  final Uint8List bytes;

  /// As the recorder reports it, for example `audio/webm;codecs=opus`.
  final String contentType;
  final Duration duration;

  /// The media type without parameters (`audio/webm`), which is what the
  /// service looks at.
  String get mediaType => contentType.split(';').first.trim().toLowerCase();

  /// A file name that matches the type, for the upload.
  String get filename => switch (mediaType) {
        'audio/ogg' => 'speech.ogg',
        'audio/wav' || 'audio/x-wav' => 'speech.wav',
        'audio/mp4' => 'speech.mp4',
        'audio/mpeg' => 'speech.mp3',
        _ => 'speech.webm',
      };
}

/// The microphone could not be used; [message] is safe to show.
class AudioRecorderException implements Exception {
  const AudioRecorderException(this.message);

  final String message;

  @override
  String toString() => 'AudioRecorderException: $message';
}

/// A push-to-talk microphone recorder: audio only, one clip at a time, at
/// most [maxDuration] long. Every microphone track is released as soon as the
/// clip is finished or cancelled. The recording is processed by the service
/// in memory and never stored.
abstract interface class AudioRecorder {
  /// The longest a clip may be; recording stops by itself then.
  Duration get maxDuration;

  /// True when this device can record audio.
  bool get isSupported;

  /// True between [start] and the end of the clip.
  bool get isRecording;

  /// Asks for the microphone and starts recording. [onLimit] is called when
  /// [maxDuration] is reached and the recorder stopped by itself; the clip is
  /// then returned by [stop]. Throws an [AudioRecorderException] when the
  /// microphone is blocked, missing or not supported.
  Future<void> start({void Function()? onLimit});

  /// Ends the clip and returns it; null when nothing was recorded or the
  /// recording was cancelled. Safe to call after the limit stopped it.
  Future<AudioClip?> stop();

  /// Throws the clip away and releases the microphone.
  Future<void> cancel();
}

/// Makes a recorder when the first one is needed (browser vs test double).
typedef AudioRecorderFactory = AudioRecorder Function();
