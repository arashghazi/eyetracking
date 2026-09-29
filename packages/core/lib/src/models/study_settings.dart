/// A study with its retention policy, and the result of a data deletion.
library;

/// What happens to research rows when a participant withdraws and erases
/// their data. The identity link is never kept.
abstract final class RetentionPolicy {
  static const deleteAll = 'delete_all';
  static const keepCoded = 'keep_coded';

  static const all = [deleteAll, keepCoded];

  static String label(String policy) => switch (policy) {
        deleteAll => 'Delete everything',
        keepCoded => 'Keep coded research rows',
        _ => policy,
      };

  static String explanation(String policy) => switch (policy) {
        deleteAll => 'When a participant erases their data, all of their '
            'research rows are deleted too. This is the default.',
        keepCoded => 'When a participant erases their data, the coded '
            'research rows stay. The link to the person is always removed.',
        _ => '',
      };
}

/// `{id, name, retention_policy}`.
class StudyInfo {
  const StudyInfo({
    required this.id,
    required this.name,
    this.retentionPolicy = RetentionPolicy.deleteAll,
  });

  final int id;
  final String name;
  final String retentionPolicy;

  StudyInfo copyWith({String? name, String? retentionPolicy}) => StudyInfo(
        id: id,
        name: name ?? this.name,
        retentionPolicy: retentionPolicy ?? this.retentionPolicy,
      );

  factory StudyInfo.fromJson(Map<String, dynamic> json) => StudyInfo(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        retentionPolicy:
            json['retention_policy'] as String? ?? RetentionPolicy.deleteAll,
      );
}

/// `POST /me/erase` answer: the policy that applied and what was deleted.
class EraseResult {
  const EraseResult({
    this.policy = RetentionPolicy.deleteAll,
    this.deleted = const {},
    this.identityRemoved = false,
  });

  final String policy;

  /// Row counts by kind (sessions, samples, events, consents, ...).
  final Map<String, int> deleted;
  final bool identityRemoved;

  factory EraseResult.fromJson(Map<String, dynamic> json) {
    final deleted = json['deleted'];
    return EraseResult(
      policy: json['policy']?.toString() ?? RetentionPolicy.deleteAll,
      deleted: {
        if (deleted is Map)
          for (final e in deleted.entries)
            if (e.value is num) '${e.key}': (e.value as num).toInt(),
      },
      identityRemoved: json['identity_removed'] == true,
    );
  }
}
