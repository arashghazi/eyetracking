import 'study.dart';

abstract class StudiesRepository {
  Future<List<Study>> list();

  /// Admin only.
  Future<Study> create(String name);
}
