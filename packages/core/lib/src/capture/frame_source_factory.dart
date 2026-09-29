// Picks the browser implementation on web and the throwing stub elsewhere.
export 'frame_source_stub.dart'
    if (dart.library.js_interop) 'frame_source_web.dart';
