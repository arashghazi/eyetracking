/// The five sections an information sheet must contain.
class SheetContent {
  const SheetContent({
    this.aims = '',
    this.discomfortSources = '',
    this.benefits = '',
    this.dataHandling = '',
    this.stopRules = '',
  });

  final String aims;
  final String discomfortSources;
  final String benefits;
  final String dataHandling;
  final String stopRules;

  bool get isComplete => [aims, discomfortSources, benefits, dataHandling, stopRules]
      .every((s) => s.trim().isNotEmpty);

  Map<String, dynamic> toJson() => {
        'aims': aims,
        'discomfort_sources': discomfortSources,
        'benefits': benefits,
        'data_handling': dataHandling,
        'stop_rules': stopRules,
      };
}

class InformationSheet {
  const InformationSheet({
    required this.version,
    required this.content,
    this.publishedAt,
  });

  final int version;
  final SheetContent content;
  final String? publishedAt;

  factory InformationSheet.fromJson(Map<String, dynamic> json) =>
      InformationSheet(
        version: (json['version'] as num).toInt(),
        publishedAt: json['published_at'] as String?,
        content: SheetContent(
          aims: json['aims'] as String? ?? '',
          discomfortSources: json['discomfort_sources'] as String? ?? '',
          benefits: json['benefits'] as String? ?? '',
          dataHandling: json['data_handling'] as String? ?? '',
          stopRules: json['stop_rules'] as String? ?? '',
        ),
      );
}
