/// Server-side quality control of one session (step 4).
library;

/// The three grades a session can get.
abstract final class QualityGrade {
  static const ok = 'ok';
  static const review = 'review';
  static const exclude = 'exclude';

  static const all = [ok, review, exclude];
}

/// Plain-language name for a quality grade.
String qualityGradeLabel(String grade) => switch (grade) {
      QualityGrade.ok => 'OK',
      QualityGrade.review => 'Review',
      QualityGrade.exclude => 'Exclude',
      _ => grade,
    };

/// Plain-language text for one quality reason code, for example
/// `uncertain_share_above_0.2` -> "Uncertain share above 20 %".
String qualityReasonLabel(String reason) {
  const fixed = {
    'synthetic_estimator': 'Recorded with the development (synthetic) estimator',
    'no_calibration': 'No valid calibration',
    'no_classifiable_time': 'No classifiable time',
    'validation_not_passed': 'Regional validation not passed',
    'ended_early': 'Ended early',
    'calibration_invalidated': 'Calibration invalidated during the session',
  };
  final known = fixed[reason];
  if (known != null) return known;
  final threshold = RegExp(r'^(uncertain|missing)_share_above_(.+)$')
      .firstMatch(reason);
  if (threshold != null) {
    final share = double.tryParse(threshold.group(2)!);
    final what = threshold.group(1) == 'uncertain' ? 'Uncertain' : 'Missing';
    final limit = share == null
        ? threshold.group(2)!
        : '${_percentText(share * 100)} %';
    return '$what share above $limit';
  }
  if (reason.isEmpty) return reason;
  final text = reason.replaceAll('_', ' ');
  return text[0].toUpperCase() + text.substring(1);
}

String _percentText(double pct) => (pct - pct.round()).abs() < 1e-6
    ? '${pct.round()}'
    : pct.toStringAsFixed(1);

/// `quality: {grade, reasons}` inside a session summary, list row or replay.
class SessionQuality {
  const SessionQuality({required this.grade, this.reasons = const []});

  final String grade;
  final List<String> reasons;

  bool get isOk => grade == QualityGrade.ok;
  bool get isReview => grade == QualityGrade.review;
  bool get isExcluded => grade == QualityGrade.exclude;

  /// All reasons, one per line, in plain language (for a tooltip).
  String get reasonsText => reasons.isEmpty
      ? 'No quality problem found.'
      : [for (final r in reasons) qualityReasonLabel(r)].join('\n');

  /// Short text for a table cell: the first reason and how many more.
  String get shortReason {
    if (reasons.isEmpty) return '';
    final first = qualityReasonLabel(reasons.first);
    return reasons.length == 1 ? first : '$first (+${reasons.length - 1})';
  }

  static SessionQuality? maybeFromJson(Object? value) {
    if (value is String) return SessionQuality(grade: value);
    if (value is! Map<String, dynamic>) return null;
    final reasons = value['reasons'];
    return SessionQuality(
      grade: value['grade']?.toString() ?? QualityGrade.review,
      reasons: [
        if (reasons is List)
          for (final r in reasons) r.toString(),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SessionQuality &&
      other.grade == grade &&
      other.reasons.length == reasons.length &&
      [for (var i = 0; i < reasons.length; i++) other.reasons[i] == reasons[i]]
          .every((e) => e);

  @override
  int get hashCode => Object.hash(grade, Object.hashAll(reasons));
}
