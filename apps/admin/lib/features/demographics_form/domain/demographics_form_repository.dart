import 'package:eyetracking_core/eyetracking_core.dart';

abstract class DemographicsFormRepository {
  /// The study's current form, or null when none is published.
  Future<DemographicsForm?> current(int studyId);

  /// Publishes [fields] as a new version.
  Future<DemographicsForm> publish(int studyId, List<DemographicsField> fields);
}
