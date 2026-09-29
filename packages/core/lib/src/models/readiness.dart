/// Machine-readable reasons the server gives when a participant is not ready.
abstract final class ReadinessReason {
  static const noInformationSheet = 'no_information_sheet_published';
  static const consentMissingOrOutdated = 'consent_missing_or_outdated';
  static const demographicsIncomplete = 'demographics_incomplete';
}

/// Plain-language text for a readiness reason code.
String readinessReasonLabel(String reason) => switch (reason) {
      ReadinessReason.noInformationSheet => 'No information sheet published',
      ReadinessReason.consentMissingOrOutdated => 'Consent missing or outdated',
      ReadinessReason.demographicsIncomplete => 'Demographics incomplete',
      _ => reason,
    };

class Readiness {
  const Readiness({required this.ready, this.reasons = const []});

  final bool ready;
  final List<String> reasons;

  factory Readiness.fromJson(Map<String, dynamic> json) => Readiness(
        ready: json['ready'] == true,
        reasons: [
          for (final r in (json['reasons'] as List<dynamic>? ?? const []))
            r.toString(),
        ],
      );

  bool has(String reason) => reasons.contains(reason);
}
