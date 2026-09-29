// Picks the browser file dialog on web and a stub elsewhere.
export 'media_picker_stub.dart' if (dart.library.js_interop) 'media_picker_web.dart';
