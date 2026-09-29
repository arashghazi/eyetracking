import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/home_repository.dart';
import '../domain/participant_overview.dart';

enum StepStatus { done, todo, waiting, optional }

class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.title,
    required this.status,
    required this.detail,
  });

  /// Stable identifier: `consent`, `demographics` or `profile`.
  final String id;
  final String title;
  final StepStatus status;
  final String detail;
}

class HomeController extends SafeChangeNotifier {
  HomeController(this._repository);

  final HomeRepository _repository;

  ParticipantOverview? _overview;
  bool _loading = false;
  String? _error;

  ParticipantOverview? get overview => _overview;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _overview = await _repository.loadOverview();
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }

  bool get isReady => _overview?.readiness.ready ?? false;

  /// The checklist shown on the home screen, derived from the server's
  /// readiness reasons.
  List<ChecklistItem> get checklist {
    final readiness = _overview?.readiness;
    if (readiness == null) return const [];

    final ChecklistItem consent;
    if (readiness.has(ReadinessReason.noInformationSheet)) {
      consent = const ChecklistItem(
        id: 'consent',
        title: 'Information sheet & consent',
        status: StepStatus.waiting,
        detail: 'The research team has not published the information sheet yet.',
      );
    } else if (readiness.has(ReadinessReason.consentMissingOrOutdated)) {
      consent = const ChecklistItem(
        id: 'consent',
        title: 'Information sheet & consent',
        status: StepStatus.todo,
        detail: 'Read the information sheet and say whether you agree to take part.',
      );
    } else {
      consent = const ChecklistItem(
        id: 'consent',
        title: 'Information sheet & consent',
        status: StepStatus.done,
        detail: 'Your consent is on file. You can review or withdraw it.',
      );
    }

    final demographics = readiness.has(ReadinessReason.demographicsIncomplete)
        ? const ChecklistItem(
            id: 'demographics',
            title: 'Demographics',
            status: StepStatus.todo,
            detail: 'A few questions the research team needs from you.',
          )
        : const ChecklistItem(
            id: 'demographics',
            title: 'Demographics',
            status: StepStatus.done,
            detail: 'Complete. You can update your answers.',
          );

    const profile = ChecklistItem(
      id: 'profile',
      title: 'Profile',
      status: StepStatus.optional,
      detail: 'Optional. Choose how you like to respond and what you enjoy.',
    );

    return [consent, demographics, profile];
  }
}
