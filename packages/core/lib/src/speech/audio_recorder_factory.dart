// Picks the browser recorder on web and an unsupported stub elsewhere.
export 'audio_recorder_stub.dart'
    if (dart.library.js_interop) 'audio_recorder_web.dart';
