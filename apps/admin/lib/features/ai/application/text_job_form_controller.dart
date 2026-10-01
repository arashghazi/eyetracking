import 'package:eyetracking_core/eyetracking_core.dart';

import '../../assignments/domain/assignments_repository.dart';
import '../domain/ai_repository.dart';

enum TextJobMode { assignment, freeForm }

/// The "Generate conversation text" form: either for one of a participant's
/// assignments that waits for content, or free-form. All checks that the
/// server repeats are made here first so the researcher sees them next to the
/// field; the server's own refusals (budget, provider) come back verbatim.
class TextJobFormController extends SafeChangeNotifier {
  TextJobFormController(
    this._repository,
    this._assignments,
    this.studyId, {
    this.onCreated,
  });

  /// Assignment statuses that can receive generated content.
  static const waitingStatuses = [
    AssignmentStatus.contentPending,
    AssignmentStatus.pendingTopic,
  ];

  final AiRepository _repository;
  final AssignmentsRepository _assignments;
  final int studyId;

  /// Called with the new job (it goes to the top of the jobs table).
  final void Function(AiJob job)? onCreated;

  TextJobMode _mode = TextJobMode.assignment;

  // Assignment mode.
  String participantCode = '';
  List<Assignment> _waiting = const [];
  String? _assignmentId;
  bool _loadingAssignments = false;
  bool _assignmentsLoaded = false;
  String? _assignmentsError;

  // Free-form mode.
  String topic = '';
  String displayName = '';
  final List<String> interests = [];

  // Shared.
  String interactionPoints = '${TextJobRequest.defaultInteractionPoints}';
  String lengthSeconds = '${TextJobRequest.defaultLengthSeconds}';
  String title = '';
  String faceId = '';
  String voiceId = '';

  bool _busy = false;
  String? _error;
  String? _notice;
  Map<String, String> _fieldErrors = const {};

  TextJobMode get mode => _mode;
  bool get isAssignmentMode => _mode == TextJobMode.assignment;

  /// The participant's assignments that wait for a topic or for content.
  List<Assignment> get waitingAssignments => _waiting;
  String? get assignmentId => _assignmentId;
  bool get loadingAssignments => _loadingAssignments;
  bool get assignmentsLoaded => _assignmentsLoaded;
  String? get assignmentsError => _assignmentsError;
  bool get busy => _busy;

  /// The server's refusal (or another failure) of the last submit.
  String? get error => _error;
  String? get notice => _notice;

  /// Messages by field: `assignment`, `code`, `topic`, `points`, `length`.
  Map<String, String> get fieldErrors => _fieldErrors;

  void setMode(TextJobMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _error = null;
    _notice = null;
    _fieldErrors = const {};
    notifyListeners();
  }

  // ------------------------------------------------------------ assignments

  Future<void> loadAssignments() async {
    final code = participantCode.trim();
    if (code.isEmpty) {
      _fieldErrors = {'code': 'Enter the participant code.'};
      notifyListeners();
      return;
    }
    _loadingAssignments = true;
    _assignmentsError = null;
    _assignmentId = null;
    _fieldErrors = const {};
    notifyListeners();
    try {
      final all = await _assignments.list(studyId, code);
      // A live conversation has no prepared content: its confirmed topic is
      // all the avatar may talk about, so there is nothing to generate.
      _waiting = [
        for (final a in all)
          if (waitingStatuses.contains(a.status) &&
              a.protocol.path != ProtocolPath.liveConversation)
            a,
      ];
      _assignmentsLoaded = true;
      if (_waiting.length == 1) _assignmentId = _waiting.first.id;
    } catch (e) {
      _waiting = const [];
      _assignmentsLoaded = false;
      _assignmentsError = userMessage(e);
    } finally {
      _loadingAssignments = false;
      notifyListeners();
    }
  }

  void selectAssignment(String? id) {
    _assignmentId = id;
    _fieldErrors = {
      for (final e in _fieldErrors.entries)
        if (e.key != 'assignment') e.key: e.value,
    };
    notifyListeners();
  }

  /// A typed participant code invalidates the list that was loaded for
  /// another code.
  void codeChanged(String value) {
    participantCode = value;
    if (_assignmentsLoaded || _waiting.isNotEmpty || _assignmentId != null) {
      _waiting = const [];
      _assignmentsLoaded = false;
      _assignmentId = null;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ interests

  void addInterest(String text) {
    final t = text.trim();
    if (t.isEmpty || interests.contains(t)) return;
    interests.add(t);
    notifyListeners();
  }

  void removeInterest(String text) {
    interests.remove(text);
    notifyListeners();
  }

  // ------------------------------------------------------------ submit

  /// Whole number in [min]..[max], or null.
  static int? _wholeNumber(String text, int min, int max) {
    final v = int.tryParse(text.trim());
    return v == null || v < min || v > max ? null : v;
  }

  Map<String, String> validate() {
    final errors = <String, String>{};
    if (isAssignmentMode) {
      if (participantCode.trim().isEmpty) {
        errors['code'] = 'Enter the participant code.';
      } else if (_assignmentId == null) {
        errors['assignment'] = 'Choose an assignment.';
      }
    } else if (topic.trim().isEmpty) {
      errors['topic'] = 'The topic is required.';
    }
    if (_wholeNumber(interactionPoints, TextJobRequest.minInteractionPoints,
            TextJobRequest.maxInteractionPoints) ==
        null) {
      errors['points'] = 'Use a whole number from '
          '${TextJobRequest.minInteractionPoints} to '
          '${TextJobRequest.maxInteractionPoints}.';
    }
    if (_wholeNumber(lengthSeconds, TextJobRequest.minLengthSeconds,
            TextJobRequest.maxLengthSeconds) ==
        null) {
      errors['length'] = 'Use a whole number of seconds from '
          '${TextJobRequest.minLengthSeconds} to '
          '${TextJobRequest.maxLengthSeconds}.';
    }
    return errors;
  }

  Future<AiJob?> submit() async {
    if (_busy) return null;
    _error = null;
    _notice = null;
    _fieldErrors = validate();
    if (_fieldErrors.isNotEmpty) {
      notifyListeners();
      return null;
    }
    final points = int.parse(interactionPoints.trim());
    final length = int.parse(lengthSeconds.trim());
    final request = isAssignmentMode
        ? TextJobRequest(
            assignmentId: _assignmentId,
            interactionPoints: points,
            lengthSeconds: length,
            title: title,
            faceId: faceId,
            voiceId: voiceId,
          )
        : TextJobRequest(
            topic: topic,
            displayName: displayName,
            interests: List.of(interests),
            interactionPoints: points,
            lengthSeconds: length,
            title: title,
            faceId: faceId,
            voiceId: voiceId,
          );
    _busy = true;
    notifyListeners();
    try {
      final job = await _repository.createTextJob(studyId, request);
      _notice = 'Text job ${job.id} queued. It creates a draft content item '
          'that you review before anything reaches a participant.';
      onCreated?.call(job);
      return job;
    } catch (e) {
      _error = userMessage(e);
      return null;
    } finally {
      _busy = false;
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
