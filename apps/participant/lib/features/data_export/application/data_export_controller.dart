import 'dart:convert';
import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/data_export_repository.dart';

/// The "Download my data" screen: fetches everything the service stores
/// about the signed-in participant, counts it and offers it as a JSON file.
class DataExportController extends SafeChangeNotifier {
  DataExportController(this._repository, this._save);

  /// The name of the downloaded file.
  static const filename = 'my-eyetracking-data.json';

  final DataExportRepository _repository;
  final FileSaver _save;

  Object? _data;
  MyDataCounts? _counts;
  bool _loading = false;
  bool _downloading = false;
  String? _error;
  String? _notice;

  /// What the file holds, once loaded.
  MyDataCounts? get counts => _counts;
  bool get loaded => _data != null;
  bool get loading => _loading;
  bool get downloading => _downloading;
  String? get error => _error;
  String? get notice => _notice;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _repository.fetchMyData();
      _data = data;
      _counts = MyDataCounts.fromJson(data);
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// The file's content: readable JSON, with each gaze sample on one line.
  Uint8List? fileBytes() {
    final data = _data;
    return data == null ? null : Uint8List.fromList(utf8.encode(prettyJson(data)));
  }

  /// Hands the data to the browser as a file.
  Future<bool> download() async {
    final bytes = fileBytes();
    if (bytes == null || _downloading) return false;
    _downloading = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      final saved = await _save(bytes, filename, 'application/json');
      if (saved) {
        _notice = 'Your data was downloaded as $filename.';
      } else {
        _error = 'Downloads are available in the web app.';
      }
      return saved;
    } catch (_) {
      _error = 'The file could not be saved. Please try again.';
      return false;
    } finally {
      _downloading = false;
      notifyListeners();
    }
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }

  void dismissNotice() {
    _notice = null;
    notifyListeners();
  }
}

/// JSON with indentation, except that a list of rows (such as the gaze
/// samples `[t_ms, x, y, conf, region]`) puts each row on one line: a
/// session has thousands of them and one line per number would be unreadable.
String prettyJson(Object? value, [int level = 0]) {
  String pad(int n) => '  ' * n;
  if (value is Map) {
    if (value.isEmpty) return '{}';
    final entries = [
      for (final e in value.entries)
        '${pad(level + 1)}${jsonEncode('${e.key}')}: ${prettyJson(e.value, level + 1)}',
    ];
    return '{\n${entries.join(',\n')}\n${pad(level)}}';
  }
  if (value is List) {
    if (value.isEmpty) return '[]';
    final flat = value.every((e) => e is! Map && e is! List);
    if (flat) return jsonEncode(value);
    final rows = value.every((e) => e is List && e.every((x) => x is! Map && x is! List));
    final items = [
      for (final e in value)
        '${pad(level + 1)}${rows ? jsonEncode(e) : prettyJson(e, level + 1)}',
    ];
    return '[\n${items.join(',\n')}\n${pad(level)}]';
  }
  return jsonEncode(value);
}
