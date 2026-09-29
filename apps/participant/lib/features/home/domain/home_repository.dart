import 'participant_overview.dart';

abstract class HomeRepository {
  Future<ParticipantOverview> loadOverview();
}
