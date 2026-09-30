/// AI content generation (build step 5): provider status, budget, jobs and
/// the requests that create them. API keys never reach the app; it only sees
/// whether a provider is configured.
library;

double _num(Object? v, [double fallback = 0]) =>
    (v as num?)?.toDouble() ?? fallback;

String? _text(Object? v) {
  final s = v?.toString();
  return s == null || s.isEmpty ? null : s;
}

Map<String, dynamic> _map(Object? v) =>
    v is Map<String, dynamic> ? v : const <String, dynamic>{};

/// The server stores ids as numbers; the app keeps them as text.
Object _wireId(String id) => int.tryParse(id) ?? id;

/// One provider (text or video) as the server reports it.
class AiProviderStatus {
  const AiProviderStatus({
    this.name = '',
    this.model,
    this.configured = false,
    this.synthetic = false,
  });

  final String name;

  /// The text model; the video provider has none.
  final String? model;
  final bool configured;

  /// The fake development provider: no key, no cost, sample content.
  final bool synthetic;

  factory AiProviderStatus.fromJson(Object? value) {
    final json = _map(value);
    return AiProviderStatus(
      name: json['name']?.toString() ?? '',
      model: _text(json['model']),
      configured: json['configured'] == true,
      synthetic: json['synthetic'] == true,
    );
  }
}

/// The study's spending cap, an estimate in USD units.
class AiBudget {
  const AiBudget({
    this.costCapUnits = 0,
    this.spentUnits = 0,
    this.remainingUnits = 0,
    this.unit = 'usd_estimate',
  });

  final double costCapUnits;
  final double spentUnits;
  final double remainingUnits;
  final String unit;

  factory AiBudget.fromJson(Object? value) {
    var json = _map(value);
    if (json['budget'] is Map<String, dynamic>) json = _map(json['budget']);
    final cap = _num(json['cost_cap_units']);
    final spent = _num(json['spent_units']);
    return AiBudget(
      costCapUnits: cap,
      spentUnits: spent,
      remainingUnits: _num(json['remaining_units'], cap - spent),
      unit: json['unit']?.toString() ?? 'usd_estimate',
    );
  }
}

/// The background worker that runs queued jobs.
class AiWorkerStatus {
  const AiWorkerStatus({this.enabled = false, this.intervalS = 0});

  final bool enabled;
  final int intervalS;

  factory AiWorkerStatus.fromJson(Object? value) {
    final json = _map(value);
    return AiWorkerStatus(
      enabled: json['enabled'] == true,
      intervalS: (json['interval_s'] as num?)?.toInt() ?? 0,
    );
  }
}

/// `GET /studies/{id}/ai/status`.
class AiStatus {
  const AiStatus({
    this.textProvider = const AiProviderStatus(),
    this.videoProvider = const AiProviderStatus(),
    this.budget = const AiBudget(),
    this.worker = const AiWorkerStatus(),
    this.sendFreeText = false,
  });

  final AiProviderStatus textProvider;
  final AiProviderStatus videoProvider;
  final AiBudget budget;
  final AiWorkerStatus worker;

  /// Study setting `ai_send_free_text`: whether a participant's free-text
  /// topic may be sent to the text provider.
  final bool sendFreeText;

  AiStatus copyWith({AiBudget? budget}) => AiStatus(
        textProvider: textProvider,
        videoProvider: videoProvider,
        budget: budget ?? this.budget,
        worker: worker,
        sendFreeText: sendFreeText,
      );

  factory AiStatus.fromJson(Map<String, dynamic> json) => AiStatus(
        textProvider: AiProviderStatus.fromJson(json['text_provider']),
        videoProvider: AiProviderStatus.fromJson(json['video_provider']),
        budget: AiBudget.fromJson(json['budget']),
        worker: AiWorkerStatus.fromJson(json['worker']),
        sendFreeText: json['send_free_text'] == true,
      );
}

abstract final class AiJobKind {
  static const text = 'text';
  static const video = 'video';
}

abstract final class AiJobStatus {
  static const queued = 'queued';
  static const running = 'running';
  static const succeeded = 'succeeded';
  static const failed = 'failed';
  static const cancelled = 'cancelled';

  /// Statuses that will still change without anyone acting.
  static bool isActive(String status) => status == queued || status == running;
}

/// Plain-language label for a job status.
String aiJobStatusLabel(String status) => switch (status) {
      AiJobStatus.queued => 'Queued',
      AiJobStatus.running => 'Running',
      AiJobStatus.succeeded => 'Succeeded',
      AiJobStatus.failed => 'Failed',
      AiJobStatus.cancelled => 'Cancelled',
      _ => status,
    };

/// One generation job (conversation text or one segment's video).
class AiJob {
  const AiJob({
    required this.id,
    this.kind = AiJobKind.text,
    this.status = AiJobStatus.queued,
    this.provider = '',
    this.contentId,
    this.assignmentId,
    this.segmentId,
    this.attempts = 0,
    this.maxAttempts = 3,
    this.costEstimateUnits = 0,
    this.costActualUnits,
    this.error,
    this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.request = const {},
    this.result = const {},
  });

  final String id;
  final String kind;
  final String status;
  final String provider;
  final String? contentId;
  final String? assignmentId;
  final String? segmentId;
  final int attempts;
  final int maxAttempts;
  final double costEstimateUnits;
  final double? costActualUnits;
  final String? error;
  final String? createdAt;
  final String? startedAt;
  final String? finishedAt;
  final Map<String, dynamic> request;
  final Map<String, dynamic> result;

  bool get isActive => AiJobStatus.isActive(status);
  bool get canCancel => status == AiJobStatus.queued;
  bool get canRetry => status == AiJobStatus.failed;

  factory AiJob.fromJson(Map<String, dynamic> json) => AiJob(
        id: json['id']?.toString() ?? '',
        kind: json['kind']?.toString() ?? AiJobKind.text,
        status: json['status']?.toString() ?? AiJobStatus.queued,
        provider: json['provider']?.toString() ?? '',
        contentId: _text(json['content_id']),
        assignmentId: _text(json['assignment_id']),
        segmentId: _text(json['segment_id']),
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        maxAttempts: (json['max_attempts'] as num?)?.toInt() ?? 3,
        costEstimateUnits: _num(json['cost_estimate_units']),
        costActualUnits: (json['cost_actual_units'] as num?)?.toDouble(),
        error: _text(json['error']),
        createdAt: _text(json['created_at']),
        startedAt: _text(json['started_at']),
        finishedAt: _text(json['finished_at']),
        request: _map(json['request']),
        result: _map(json['result']),
      );
}

/// `POST /studies/{id}/ai/text-jobs`. With [assignmentId] the topic, display
/// name and interests come from the assignment and profile on the server, so
/// only the free-form request carries them.
class TextJobRequest {
  const TextJobRequest({
    this.assignmentId,
    this.topic,
    this.displayName,
    this.interests = const [],
    this.interactionPoints = defaultInteractionPoints,
    this.lengthSeconds = defaultLengthSeconds,
    this.title,
    this.faceId,
    this.voiceId,
  });

  static const minInteractionPoints = 0;
  static const maxInteractionPoints = 5;
  static const defaultInteractionPoints = 2;
  static const minLengthSeconds = 30;
  static const maxLengthSeconds = 600;
  static const defaultLengthSeconds = 90;

  final String? assignmentId;
  final String? topic;
  final String? displayName;
  final List<String> interests;
  final int interactionPoints;
  final int lengthSeconds;
  final String? title;
  final String? faceId;
  final String? voiceId;

  Map<String, dynamic> toJson() {
    void put(Map<String, dynamic> m, String key, String? v) {
      final t = v?.trim();
      if (t != null && t.isNotEmpty) m[key] = t;
    }

    final json = <String, dynamic>{};
    if (assignmentId != null) json['assignment_id'] = _wireId(assignmentId!);
    put(json, 'topic', topic);
    put(json, 'display_name', displayName);
    if (interests.isNotEmpty) json['interests'] = interests;
    json['interaction_points'] = interactionPoints;
    json['length_seconds'] = lengthSeconds;
    put(json, 'title', title);
    put(json, 'face_id', faceId);
    put(json, 'voice_id', voiceId);
    return json;
  }
}

/// `POST /studies/{id}/ai/video-jobs`: one job per segment without media.
class VideoJobRequest {
  const VideoJobRequest({
    required this.contentId,
    this.segmentIds = const [],
    this.faceId,
    this.voiceId,
  });

  final String contentId;

  /// Empty means every segment that has no uploaded media.
  final List<String> segmentIds;
  final String? faceId;
  final String? voiceId;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'content_id': _wireId(contentId)};
    if (segmentIds.isNotEmpty) json['segment_ids'] = segmentIds;
    final face = faceId?.trim();
    if (face != null && face.isNotEmpty) json['face_id'] = face;
    final voice = voiceId?.trim();
    if (voice != null && voice.isNotEmpty) json['voice_id'] = voice;
    return json;
  }
}

/// `POST /studies/{id}/ai/run`: what "Run queued jobs now" did.
class AiRunResult {
  const AiRunResult({this.processed = 0, this.succeeded = 0, this.failed = 0});

  final int processed;
  final int succeeded;
  final int failed;

  factory AiRunResult.fromJson(Map<String, dynamic> json) => AiRunResult(
        processed: (json['processed'] as num?)?.toInt() ?? 0,
        succeeded: (json['succeeded'] as num?)?.toInt() ?? 0,
        failed: (json['failed'] as num?)?.toInt() ?? 0,
      );
}
