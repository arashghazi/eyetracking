import 'protocol.dart';

/// Where an assignment stands, from the participant's and the researcher's
/// point of view.
abstract final class AssignmentStatus {
  static const pendingTopic = 'pending_topic';
  static const contentPending = 'content_pending';
  static const ready = 'ready';
  static const inProgress = 'in_progress';
  static const completed = 'completed';
  static const cancelled = 'cancelled';
}

/// Plain-language label for an assignment status.
String assignmentStatusLabel(String status) => switch (status) {
      AssignmentStatus.pendingTopic => 'Topic needed',
      AssignmentStatus.contentPending => 'Content being prepared',
      AssignmentStatus.ready => 'Ready',
      AssignmentStatus.inProgress => 'In progress',
      AssignmentStatus.completed => 'Completed',
      AssignmentStatus.cancelled => 'Cancelled',
      _ => status,
    };

/// One protocol assigned to a participant.
class Assignment {
  const Assignment({
    required this.id,
    this.orderIndex = 0,
    this.status = AssignmentStatus.ready,
    required this.protocol,
    this.topic,
    this.topicFreeText,
    this.contentId,
    this.contentTitle,
    this.createdAt,
  });

  final String id;
  final int orderIndex;
  final String status;
  final ProtocolRef protocol;
  final String? topic;
  final String? topicFreeText;
  final String? contentId;
  final String? contentTitle;
  final String? createdAt;

  bool get isInterest => protocol.path == ProtocolPath.interestConversation;

  /// Step 7: a live conversation with an avatar (no prepared content).
  bool get isLive => protocol.path == ProtocolPath.liveConversation;
  bool get canStartSession =>
      status == AssignmentStatus.ready || status == AssignmentStatus.inProgress;

  factory Assignment.fromJson(Map<String, dynamic> json) => Assignment(
        id: json['id']?.toString() ?? '',
        orderIndex: (json['order_index'] as num?)?.toInt() ?? 0,
        status: json['status']?.toString() ?? AssignmentStatus.ready,
        protocol: ProtocolRef.maybeFromJson(json['protocol']) ??
            const ProtocolRef(id: '', name: ''),
        topic: _text(json['topic']),
        topicFreeText: _text(json['topic_free_text']),
        contentId: _text(json['content_id']),
        contentTitle: _text(json['content_title']),
        createdAt: json['created_at']?.toString(),
      );

  static String? _text(Object? v) {
    final s = v?.toString();
    return s == null || s.isEmpty ? null : s;
  }
}
