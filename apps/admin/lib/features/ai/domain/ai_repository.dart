import 'package:eyetracking_core/eyetracking_core.dart';

/// AI generation endpoints of the step 5 contract. Provider keys stay on the
/// server; the app sees only whether a provider is configured.
abstract class AiRepository {
  Future<AiStatus> status(int studyId);

  /// Sets the cost cap (administrators). A refusal is a 422 whose message is
  /// shown as the server wrote it.
  Future<AiBudget> setBudget(int studyId, double costCapUnits);

  /// Switches whether a participant's free-text topic may be sent to the text
  /// provider (administrators; `PUT budget {send_free_text}`). Returns the
  /// setting as the server stored it.
  Future<bool> setSendFreeText(int studyId, bool value);

  /// Creates a draft content item and the job that fills it. Refused with
  /// `budget_exceeded` or `provider_not_configured` when it cannot run.
  Future<AiJob> createTextJob(int studyId, TextJobRequest request);

  /// One job per segment without media; 409 while the text is not reviewed.
  Future<List<AiJob>> createVideoJobs(int studyId, VideoJobRequest request);

  /// Newest first.
  Future<List<AiJob>> jobs(int studyId, {String? status, String? contentId});

  Future<AiJob> cancel(int studyId, String jobId);

  Future<AiJob> retry(int studyId, String jobId);

  /// Runs queued jobs now (the background worker does the same on a timer).
  Future<AiRunResult> run(int studyId, {int maxJobs = 5});
}
