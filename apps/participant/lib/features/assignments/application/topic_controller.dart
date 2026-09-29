import 'package:eyetracking_core/eyetracking_core.dart';

import '../../profile/domain/profile_repository.dart';
import '../domain/assignments_repository.dart';

/// The short interview that confirms the topic of an interest conversation:
/// one of the participant's interests or a topic they type, plus an optional
/// free text.
class TopicController extends SafeChangeNotifier {
  TopicController({
    required this._assignments,
    required this._profile,
    required this.assignment,
  });

  final AssignmentsRepository _assignments;
  final ProfileRepository _profile;
  final Assignment assignment;

  List<String> _interests = const [];
  String _topic = '';
  String _freeText = '';
  bool _loading = false;
  bool _submitting = false;
  bool _submitted = false;
  String? _error;

  /// Interests from the profile, offered as chips.
  List<String> get interests => _interests;
  String get topic => _topic;
  String get freeText => _freeText;
  bool get loading => _loading;
  bool get submitting => _submitting;

  /// True once the server accepted the topic: the content is now prepared.
  bool get submitted => _submitted;
  String? get error => _error;
  bool get canSubmit => _topic.trim().isNotEmpty && !_submitting && !_submitted;

  /// The chip that matches the current topic, if any.
  String? get selectedInterest {
    final t = _topic.trim().toLowerCase();
    for (final i in _interests) {
      if (i.trim().toLowerCase() == t) return i;
    }
    return null;
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _interests = (await _profile.load()).interests;
    } catch (_) {
      // The chips are a convenience; typing a topic still works.
      _interests = const [];
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Chooses an interest chip (a second tap clears it).
  void pickInterest(String interest) {
    _topic = selectedInterest == interest ? '' : interest;
    _error = null;
    notifyListeners();
  }

  void setTopic(String value) {
    _topic = value;
    _error = null;
    notifyListeners();
  }

  void setFreeText(String value) {
    _freeText = value;
    notifyListeners();
  }

  Future<bool> submit() async {
    if (!canSubmit) return false;
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      final note = _freeText.trim();
      await _assignments.submitTopic(
        assignment.id,
        topic: _topic.trim(),
        freeText: note.isEmpty ? null : note,
      );
      _submitted = true;
      return true;
    } catch (e) {
      _error = userMessage(e);
      return false;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }
}
