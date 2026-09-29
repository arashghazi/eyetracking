import 'consent.dart';
import 'demographics.dart';
import 'profile.dart';
import 'readiness.dart';

/// Coded view of one participant as researchers see it. Never carries the
/// login email; that needs the separate identity endpoint.
class ParticipantRecord {
  const ParticipantRecord({
    required this.code,
    required this.readiness,
    this.consent,
    this.profile,
    this.demographics,
  });

  final String code;
  final Readiness readiness;
  final Consent? consent;
  final Profile? profile;
  final DemographicsAnswers? demographics;

  bool get demographicsComplete =>
      !readiness.has(ReadinessReason.demographicsIncomplete);

  factory ParticipantRecord.fromJson(Map<String, dynamic> json) =>
      ParticipantRecord(
        code: json['code'] as String? ?? '',
        readiness: Readiness.fromJson(
          json['readiness'] as Map<String, dynamic>? ?? const {},
        ),
        consent: Consent.maybeFromJson(json['consent']),
        profile: json['profile'] is Map<String, dynamic>
            ? Profile.fromJson(json['profile'] as Map<String, dynamic>)
            : null,
        demographics: DemographicsAnswers.maybeFromJson(json['demographics']),
      );
}
