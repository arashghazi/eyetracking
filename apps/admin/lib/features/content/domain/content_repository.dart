import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';

/// Content endpoints of the step 3 contract.
abstract class ContentRepository {
  Future<List<ContentSummary>> list(int studyId);

  Future<ContentDetail> get(int studyId, String contentId);

  Future<ContentDetail> create(
    int studyId, {
    required String title,
    required List<String> topicTags,
    required String faceId,
    required String voiceId,
    required ContentDefinition definition,
  });

  /// Changes a draft; approved content answers 409.
  Future<ContentDetail> update(
    int studyId,
    String contentId, {
    required String title,
    required List<String> topicTags,
    required String faceId,
    required String voiceId,
    required ContentDefinition definition,
  });

  /// Approves a draft. Answers 422 while media is missing.
  Future<ContentDetail> approve(int studyId, String contentId);

  /// Marks the generated (or edited) text as reviewed. Video generation
  /// needs it; editing the definition resets it.
  Future<ContentDetail> markTextReviewed(int studyId, String contentId);

  /// Uploads the file for one media key; [onProgress] gets bytes handed to
  /// the network layer and the total.
  Future<MediaInfo> uploadMedia(
    int studyId,
    String contentId,
    String key, {
    required Uint8List bytes,
    required String filename,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  });

  /// The media uploaded so far.
  Future<List<MediaInfo>> media(int studyId, String contentId);
}
