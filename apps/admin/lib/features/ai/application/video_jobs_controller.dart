import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/ai_repository.dart';

/// The "Generate videos" section of the content editor: face and voice ids,
/// which segments (all of those without media are selected until the
/// researcher unticks some) and the jobs that were created.
class VideoJobsController extends SafeChangeNotifier {
  VideoJobsController(this._repository, this.studyId);

  final AiRepository _repository;
  final int studyId;

  String faceId = '';
  String voiceId = '';

  final Set<String> _unticked = {};
  List<AiJob> _created = const [];
  bool _busy = false;
  String? _error;

  /// Jobs created by the last successful request.
  List<AiJob> get created => _created;
  bool get busy => _busy;

  /// The server's refusal (409 when the text is not reviewed, 422 budget or
  /// provider), verbatim.
  String? get error => _error;

  bool isSelected(String segmentId) => !_unticked.contains(segmentId);

  void select(String segmentId, bool selected) {
    if (selected) {
      _unticked.remove(segmentId);
    } else {
      _unticked.add(segmentId);
    }
    notifyListeners();
  }

  /// [candidates] filtered to those still ticked.
  List<String> selectedOf(List<String> candidates) => [
        for (final id in candidates)
          if (isSelected(id)) id,
      ];

  /// Creates one job per selected segment of [contentId].
  Future<List<AiJob>> generate(
    String contentId,
    List<String> candidates,
  ) async {
    if (_busy) return const [];
    final segments = selectedOf(candidates);
    if (segments.isEmpty) return const [];
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _created = await _repository.createVideoJobs(
        studyId,
        VideoJobRequest(
          contentId: contentId,
          segmentIds: segments,
          faceId: faceId,
          voiceId: voiceId,
        ),
      );
      return _created;
    } catch (e) {
      _error = userMessage(e);
      return const [];
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }
}
