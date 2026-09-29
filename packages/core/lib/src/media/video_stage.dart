// Picks the browser player on web and a message-only stub elsewhere.
export 'video_stage_stub.dart' if (dart.library.js_interop) 'video_stage_web.dart';
