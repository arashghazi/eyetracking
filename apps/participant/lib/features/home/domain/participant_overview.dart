import 'package:eyetracking_core/eyetracking_core.dart';

/// What the participant sees about themself on the home screen.
class ParticipantOverview {
  const ParticipantOverview({
    required this.code,
    required this.studyId,
    required this.readiness,
    this.consent,
  });

  final String code;
  final int studyId;
  final Readiness readiness;
  final Consent? consent;

  factory ParticipantOverview.fromJson(Map<String, dynamic> json) =>
      ParticipantOverview(
        code: json['code'] as String? ?? '',
        studyId: (json['study_id'] as num?)?.toInt() ?? 0,
        readiness: Readiness.fromJson(
          json['readiness'] as Map<String, dynamic>? ?? const {},
        ),
        consent: Consent.maybeFromJson(json['consent']),
      );
}
