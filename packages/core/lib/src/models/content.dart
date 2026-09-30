/// Interest-path content: the researcher's authored item (admin) and the
/// personalized copy a participant plays (participant).
library;

import 'layout.dart';

double _d(Object? v, double fallback) => (v as num?)?.toDouble() ?? fallback;
List<String> _strings(Object? v) =>
    [for (final e in (v as List<dynamic>? ?? const [])) e.toString()];

/// Face, eye and mouth regions as fractions (0..1) of the video frame.
class NormalizedFaceLayout {
  const NormalizedFaceLayout({
    required this.faceBox,
    required this.eyeRegion,
    required this.mouthRegion,
  });

  final Box faceBox;
  final Box eyeRegion;
  final Box mouthRegion;

  static NormalizedFaceLayout? maybeFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final face = Box.maybeFromJson(value['face_box']);
    final eye = Box.maybeFromJson(value['eye_region']);
    final mouth = Box.maybeFromJson(value['mouth_region']);
    if (face == null || eye == null || mouth == null) return null;
    return NormalizedFaceLayout(faceBox: face, eyeRegion: eye, mouthRegion: mouth);
  }

  Map<String, dynamic> toJson() => {
        'face_box': faceBox.toJson(),
        'eye_region': eyeRegion.toJson(),
        'mouth_region': mouthRegion.toJson(),
      };

  /// Maps the fractions onto the rectangle where the video is actually drawn
  /// ([videoRect], in CSS pixels of the screen). With `object-fit: contain`
  /// that rectangle is smaller than the player when the aspect ratios differ.
  StimulusLayout toStimulusLayout(ScreenInfo screen, Box videoRect) {
    Box map(Box n) => Box(
          videoRect.x + n.x * videoRect.w,
          videoRect.y + n.y * videoRect.h,
          n.w * videoRect.w,
          n.h * videoRect.h,
        );
    return StimulusLayout(
      screen: screen,
      faceBox: map(faceBox),
      eyeRegion: map(eyeRegion),
      mouthRegion: map(mouthRegion),
    );
  }
}

/// The rectangle of a video of [videoW] x [videoH] drawn with
/// `object-fit: contain` inside [container].
Box containedVideoRect(Box container, double videoW, double videoH) {
  if (videoW <= 0 || videoH <= 0 || container.w <= 0 || container.h <= 0) {
    return container;
  }
  final scale = container.w / videoW < container.h / videoH
      ? container.w / videoW
      : container.h / videoH;
  final w = videoW * scale;
  final h = videoH * scale;
  return Box(container.x + (container.w - w) / 2,
      container.y + (container.h - h) / 2, w, h);
}

// ------------------------------------------------------------ admin side

/// A question at the end of a segment. [branches] maps an option to the id of
/// the segment played next; an option without a branch ends the conversation.
class ContentQuestion {
  const ContentQuestion({
    required this.id,
    required this.prompt,
    this.options = const [],
    this.branches = const {},
  });

  final String id;
  final String prompt;
  final List<String> options;
  final Map<String, String> branches;

  static ContentQuestion? maybeFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final branches = value['branches'];
    return ContentQuestion(
      id: value['id']?.toString() ?? '',
      prompt: value['prompt']?.toString() ?? '',
      options: _strings(value['options']),
      branches: branches is Map
          ? {for (final e in branches.entries) '${e.key}': '${e.value}'}
          : const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'prompt': prompt,
        'options': options,
        'branches': branches,
      };
}

class ContentSegment {
  const ContentSegment({
    required this.id,
    this.text = '',
    this.mediaKey = '',
    this.durationS = 10,
    this.faceLayout,
    this.question,
  });

  final String id;

  /// May contain `{{display_name}}` and `{{topic}}`.
  final String text;
  final String mediaKey;
  final double durationS;
  final NormalizedFaceLayout? faceLayout;
  final ContentQuestion? question;

  factory ContentSegment.fromJson(Map<String, dynamic> json) => ContentSegment(
        id: json['id']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        mediaKey: json['media_key']?.toString() ?? '',
        durationS: _d(json['duration_s'], 10),
        faceLayout: NormalizedFaceLayout.maybeFromJson(json['face_layout']),
        question: ContentQuestion.maybeFromJson(json['question']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'media_key': mediaKey,
        'duration_s': durationS == durationS.roundToDouble()
            ? durationS.round()
            : durationS,
        'face_layout': faceLayout?.toJson(),
        'question': question?.toJson(),
      };
}

/// A comprehension question asked after the conversation.
class ComprehensionItem {
  const ComprehensionItem({
    required this.id,
    required this.prompt,
    this.options = const [],
    this.correct = '',
  });

  final String id;
  final String prompt;
  final List<String> options;
  final String correct;

  factory ComprehensionItem.fromJson(Map<String, dynamic> json) =>
      ComprehensionItem(
        id: json['id']?.toString() ?? '',
        prompt: json['prompt']?.toString() ?? '',
        options: _strings(json['options']),
        correct: json['correct']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'prompt': prompt,
        'options': options,
        'correct': correct,
      };
}

class ContentDefinition {
  const ContentDefinition({
    this.startSegment = '',
    this.postSegment,
    this.segments = const [],
    this.comprehension = const [],
  });

  final String startSegment;
  final String? postSegment;
  final List<ContentSegment> segments;
  final List<ComprehensionItem> comprehension;

  factory ContentDefinition.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return const ContentDefinition();
    final post = value['post_segment']?.toString();
    return ContentDefinition(
      startSegment: value['start_segment']?.toString() ?? '',
      postSegment: post == null || post.isEmpty ? null : post,
      segments: [
        for (final s in (value['segments'] as List<dynamic>? ?? const []))
          ContentSegment.fromJson(s as Map<String, dynamic>),
      ],
      comprehension: [
        for (final c in (value['comprehension'] as List<dynamic>? ?? const []))
          ComprehensionItem.fromJson(c as Map<String, dynamic>),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'start_segment': startSegment,
        'post_segment': postSegment,
        'segments': [for (final s in segments) s.toJson()],
        'comprehension': [for (final c in comprehension) c.toJson()],
      };
}

abstract final class ContentStatus {
  static const draft = 'draft';
  static const approved = 'approved';
}

/// One row of the content list.
class ContentSummary {
  const ContentSummary({
    required this.id,
    required this.title,
    this.topicTags = const [],
    this.faceId = '',
    this.voiceId = '',
    this.status = ContentStatus.draft,
    this.mediaKeys = const [],
    this.missingMedia = const [],
    this.textReviewed = false,
  });

  final String id;
  final String title;
  final List<String> topicTags;
  final String faceId;
  final String voiceId;
  final String status;
  final List<String> mediaKeys;

  /// Media keys used by the segments that have no upload yet.
  final List<String> missingMedia;

  /// A researcher has read the generated (or edited) text. Editing the
  /// definition resets it; video generation needs it.
  final bool textReviewed;

  bool get isDraft => status == ContentStatus.draft;
  bool get isApproved => status == ContentStatus.approved;

  factory ContentSummary.fromJson(Map<String, dynamic> json) => ContentSummary(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        topicTags: _strings(json['topic_tags']),
        faceId: json['face_id']?.toString() ?? '',
        voiceId: json['voice_id']?.toString() ?? '',
        status: json['status']?.toString() ?? ContentStatus.draft,
        mediaKeys: _strings(json['media_keys']),
        missingMedia: _strings(json['missing_media']),
        textReviewed: json['text_reviewed'] == true,
      );
}

/// A content item with its authored definition.
class ContentDetail {
  const ContentDetail({required this.summary, required this.definition});

  final ContentSummary summary;
  final ContentDefinition definition;

  factory ContentDetail.fromJson(Map<String, dynamic> json) => ContentDetail(
        summary: ContentSummary.fromJson(json),
        definition: ContentDefinition.fromJson(json['definition']),
      );
}

/// Result of a media upload.
class MediaInfo {
  const MediaInfo({required this.key, this.contentType = '', this.size = 0});

  final String key;
  final String contentType;
  final int size;

  factory MediaInfo.fromJson(Map<String, dynamic> json) => MediaInfo(
        key: json['key']?.toString() ?? '',
        contentType: json['content_type']?.toString() ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
      );
}

// ------------------------------------------------------- participant side

/// A question as the participant sees it: no correct answer, no branches.
class PersonalizedQuestion {
  const PersonalizedQuestion({
    required this.id,
    required this.prompt,
    this.options = const [],
  });

  final String id;
  final String prompt;
  final List<String> options;

  static PersonalizedQuestion? maybeFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    return PersonalizedQuestion(
      id: value['id']?.toString() ?? '',
      prompt: value['prompt']?.toString() ?? '',
      options: _strings(value['options']),
    );
  }
}

class PersonalizedSegment {
  const PersonalizedSegment({
    required this.id,
    this.text = '',
    this.mediaUrl = '',
    this.durationS = 0,
    this.faceLayout,
    this.question,
    this.mediaKey,
  });

  final String id;

  /// The key of the media file, when the service names it (`media_key`).
  /// The signed link alone does not carry it.
  final String? mediaKey;

  /// Already personalized; shown as a caption only when the participant
  /// asked for captions.
  final String text;

  /// Signed, expiring URL. Used exactly as given.
  final String mediaUrl;
  final double durationS;
  final NormalizedFaceLayout? faceLayout;
  final PersonalizedQuestion? question;

  factory PersonalizedSegment.fromJson(Map<String, dynamic> json) =>
      PersonalizedSegment(
        id: json['id']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        mediaUrl: json['media_url']?.toString() ?? '',
        durationS: _d(json['duration_s'], 0),
        faceLayout: NormalizedFaceLayout.maybeFromJson(json['face_layout']),
        question: PersonalizedQuestion.maybeFromJson(json['question']),
        mediaKey: json['media_key']?.toString(),
      );
}

class PersonalizedContent {
  const PersonalizedContent({
    this.title = '',
    this.faceId = '',
    this.voiceId = '',
    required this.startSegment,
    this.postSegment,
    this.segments = const [],
    this.comprehension = const [],
  });

  final String title;
  final String faceId;
  final String voiceId;
  final String startSegment;
  final String? postSegment;
  final List<PersonalizedSegment> segments;
  final List<PersonalizedQuestion> comprehension;

  PersonalizedSegment? segment(String? id) {
    if (id == null) return null;
    for (final s in segments) {
      if (s.id == id) return s;
    }
    return null;
  }

  factory PersonalizedContent.fromJson(Map<String, dynamic> json) {
    final post = json['post_segment']?.toString();
    return PersonalizedContent(
      title: json['title']?.toString() ?? '',
      faceId: json['face_id']?.toString() ?? '',
      voiceId: json['voice_id']?.toString() ?? '',
      startSegment: json['start_segment']?.toString() ?? '',
      postSegment: post == null || post.isEmpty ? null : post,
      segments: [
        for (final s in (json['segments'] as List<dynamic>? ?? const []))
          PersonalizedSegment.fromJson(s as Map<String, dynamic>),
      ],
      comprehension: [
        for (final c in (json['comprehension'] as List<dynamic>? ?? const []))
          if (PersonalizedQuestion.maybeFromJson(c) != null)
            PersonalizedQuestion.maybeFromJson(c)!,
      ],
    );
  }
}
