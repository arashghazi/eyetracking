abstract class DataExportRepository {
  /// Everything the service stores about the signed-in participant.
  Future<Object?> fetchMyData();
}
