import 'package:eyetracking_core/eyetracking_core.dart';

abstract class DemographicsRepository {
  /// The study's current form, or null when none is published.
  Future<DemographicsForm?> fetchForm();

  /// The participant's saved answers, or null if they have not answered yet.
  Future<DemographicsAnswers?> fetchAnswers();

  Future<DemographicsAnswers> save(Map<String, Object?> answers);
}
