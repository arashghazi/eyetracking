import 'package:eyetracking_core/eyetracking_core.dart';

/// Protocol endpoints of the step 3 contract (researchers edit; analysts read).
abstract class ProtocolsRepository {
  Future<List<ProtocolSummary>> list(int studyId);

  Future<ProtocolDetail> get(int studyId, String protocolId);

  /// Creates a draft.
  Future<ProtocolDetail> create(
    int studyId,
    String name,
    ProtocolDefinition definition,
  );

  /// Changes a draft; a published version answers 409.
  Future<ProtocolDetail> update(
    int studyId,
    String protocolId, {
    String? name,
    ProtocolDefinition? definition,
  });

  /// The draft becomes a published, numbered version that never changes.
  Future<ProtocolDetail> publish(int studyId, String protocolId);

  /// A new draft that starts as a copy of a published version.
  Future<ProtocolDetail> newDraft(int studyId, String protocolId);
}
