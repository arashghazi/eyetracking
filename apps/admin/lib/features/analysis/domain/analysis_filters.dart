import 'package:eyetracking_core/eyetracking_core.dart';

/// The filters of the analysis view and of the session exports (the same
/// query string serves both).
class AnalysisFilters {
  const AnalysisFilters({
    this.participant = '',
    this.path,
    this.protocolVersion = '',
    this.device = '',
    this.from = '',
    this.to = '',
    this.qualities = const {QualityGrade.ok, QualityGrade.review},
    this.includeSynthetic = false,
  });

  /// Quality grades that can be selected. `exclude` sessions are never part
  /// of an analysis.
  static const selectableQualities = [QualityGrade.ok, QualityGrade.review];

  final String participant;

  /// `gradual_face` or `interest_conversation`; null for both.
  final String? path;
  final String protocolVersion;
  final String device;

  /// ISO dates (`2026-09-29`); empty for no bound.
  final String from;
  final String to;
  final Set<String> qualities;
  final bool includeSynthetic;

  AnalysisFilters copyWith({
    String? participant,
    Object? path = _keep,
    String? protocolVersion,
    String? device,
    String? from,
    String? to,
    Set<String>? qualities,
    bool? includeSynthetic,
  }) =>
      AnalysisFilters(
        participant: participant ?? this.participant,
        path: identical(path, _keep) ? this.path : path as String?,
        protocolVersion: protocolVersion ?? this.protocolVersion,
        device: device ?? this.device,
        from: from ?? this.from,
        to: to ?? this.to,
        qualities: qualities ?? this.qualities,
        includeSynthetic: includeSynthetic ?? this.includeSynthetic,
      );

  static const Object _keep = Object();

  /// A message when the filters cannot be sent, or null.
  String? validate() {
    final version = protocolVersion.trim();
    if (version.isNotEmpty && int.tryParse(version) == null) {
      return 'The protocol version must be a whole number.';
    }
    DateTime? parse(String text) => DateTime.tryParse(text.trim());
    if (from.trim().isNotEmpty && parse(from) == null) {
      return 'The "from" date must look like 2026-09-29.';
    }
    if (to.trim().isNotEmpty && parse(to) == null) {
      return 'The "to" date must look like 2026-09-29.';
    }
    if (from.trim().isNotEmpty && to.trim().isNotEmpty) {
      if (parse(from)!.isAfter(parse(to)!)) {
        return 'The "from" date is after the "to" date.';
      }
    }
    if (qualities.isEmpty) return 'Select at least one quality grade.';
    return null;
  }

  /// The grades the query asks for: the ones selected, in a fixed order.
  ///
  /// A synthetic session is always graded `exclude` (its reason is
  /// `synthetic_estimator`), so "include synthetic sessions" would list
  /// nothing unless that grade is asked for as well; switching it on adds
  /// `exclude`.
  List<String> get requestedQualities => [
        for (final g in selectableQualities)
          if (qualities.contains(g)) g,
        if (includeSynthetic) QualityGrade.exclude,
      ];

  /// The query parameters in contract order; empty filters are left out.
  /// `quality` is always sent, so the server never has to guess, and
  /// `include_synthetic` is always explicit.
  Map<String, String> toQuery() {
    final query = <String, String>{};
    void put(String key, String value) {
      final v = value.trim();
      if (v.isNotEmpty) query[key] = v;
    }

    put('participant', participant);
    if (path != null && path!.isNotEmpty) query['path'] = path!;
    put('protocol_version', protocolVersion);
    put('device', device);
    put('from', from);
    put('to', to);
    final grades = requestedQualities;
    if (grades.isNotEmpty) query['quality'] = grades.join(',');
    query['include_synthetic'] = includeSynthetic ? 'true' : 'false';
    return query;
  }

  /// `a=1&b=2`, percent-encoded; commas in `quality` stay readable.
  String get queryString => toQuery()
      .entries
      .map((e) => '${Uri.encodeQueryComponent(e.key)}='
          '${Uri.encodeQueryComponent(e.value).replaceAll('%2C', ',')}')
      .join('&');
}
