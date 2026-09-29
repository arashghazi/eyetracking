// Picks the browser download on web and a no-op elsewhere.
export 'save_file_stub.dart' if (dart.library.js_interop) 'save_file_web.dart';
