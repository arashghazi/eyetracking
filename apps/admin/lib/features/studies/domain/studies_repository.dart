import 'study.dart';

abstract class StudiesRepository {
  Future<List<Study>> list();

  /// Admin only.
  Future<Study> create(String name);

  /// One study with its retention policy.
  Future<Study> get(int studyId);

  /// Admin only: what happens to research rows when a participant erases
  /// their data (`delete_all` or `keep_coded`).
  Future<Study> setRetentionPolicy(int studyId, String policy);
}
