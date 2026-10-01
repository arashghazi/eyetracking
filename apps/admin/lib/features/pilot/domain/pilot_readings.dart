import 'package:eyetracking_core/eyetracking_core.dart';

import '../../live/domain/live_models.dart';

/// One read of the live monitor: the status of the session and, for a
/// session of the live path, the state of its conversation.
class LiveReading {
  const LiveReading(this.status, {this.conversation});

  final LiveStatus status;

  /// Null when the session has no conversation.
  final ConversationMonitor? conversation;
}

/// The pilot report with the conversation columns of its rows (the shared
/// report model does not carry them).
class PilotReportData {
  const PilotReportData(this.report, {this.conversation = const {}});

  final PilotReport report;

  /// Conversation columns by session id.
  final Map<String, ConversationReportColumns> conversation;

  /// The conversation columns of a row; all null when the server sent none.
  ConversationReportColumns columnsFor(String sessionId) =>
      conversation[sessionId] ?? const ConversationReportColumns();
}
