// Picks the browser voice on web and a silent stub elsewhere.
export 'speech_stub.dart' if (dart.library.js_interop) 'speech_web.dart';
