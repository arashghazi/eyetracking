import 'package:eyetracking_core/eyetracking_core.dart';

abstract class InformationSheetRepository {
  /// The study's current sheet, or null when none is published.
  Future<InformationSheet?> current(int studyId);

  /// Publishes [content] as a new version.
  Future<InformationSheet> publish(int studyId, SheetContent content);
}
