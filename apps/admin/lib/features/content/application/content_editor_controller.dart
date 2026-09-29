import 'dart:typed_data';

import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/content_repository.dart';
import '../domain/media_picker.dart';

String _num(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

String _boxText(Box? b) =>
    b == null ? '' : [b.x, b.y, b.w, b.h].map(_num).join(', ');

/// Reads "Option=segment" lines. A line without "=" is an option that ends
/// the conversation.
({List<String> options, Map<String, String> branches}) parseOptionLines(
  String text,
) {
  final options = <String>[];
  final branches = <String, String>{};
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final at = line.indexOf('=');
    final option = (at < 0 ? line : line.substring(0, at)).trim();
    if (option.isEmpty) continue;
    options.add(option);
    if (at >= 0) {
      final target = line.substring(at + 1).trim();
      if (target.isNotEmpty) branches[option] = target;
    }
  }
  return (options: options, branches: branches);
}

/// The lines the editor shows for a question's options and branches.
String optionLines(List<String> options, Map<String, String> branches) => [
      for (final o in options)
        branches.containsKey(o) ? '$o=${branches[o]}' : o,
    ].join('\n');

class SegmentDraft {
  SegmentDraft({
    required this.uid,
    this.id = '',
    this.text = '',
    this.mediaKey = '',
    this.duration = '10',
    this.questionId = '',
    this.questionPrompt = '',
    this.optionText = '',
    this.faceBox = '',
    this.eyeRegion = '',
    this.mouthRegion = '',
  });

  factory SegmentDraft.from(int uid, ContentSegment s) => SegmentDraft(
        uid: uid,
        id: s.id,
        text: s.text,
        mediaKey: s.mediaKey,
        duration: _num(s.durationS),
        questionId: s.question?.id ?? '',
        questionPrompt: s.question?.prompt ?? '',
        optionText: s.question == null
            ? ''
            : optionLines(s.question!.options, s.question!.branches),
        faceBox: _boxText(s.faceLayout?.faceBox),
        eyeRegion: _boxText(s.faceLayout?.eyeRegion),
        mouthRegion: _boxText(s.faceLayout?.mouthRegion),
      );

  final int uid;
  String id;
  String text;
  String mediaKey;
  String duration;
  String questionId;
  String questionPrompt;

  /// One "Option=segment" per line.
  String optionText;
  String faceBox;
  String eyeRegion;
  String mouthRegion;
}

class ComprehensionDraft {
  ComprehensionDraft({
    required this.uid,
    this.id = '',
    this.prompt = '',
    this.optionText = '',
    this.correct = '',
  });

  factory ComprehensionDraft.from(int uid, ComprehensionItem c) =>
      ComprehensionDraft(
        uid: uid,
        id: c.id,
        prompt: c.prompt,
        optionText: c.options.join('\n'),
        correct: c.correct,
      );

  final int uid;
  String id;
  String prompt;
  String optionText;
  String correct;
}

/// Progress of the upload for one media key.
class MediaUploadState {
  const MediaUploadState({this.progress, this.error, this.done = false});

  /// 0..1 while uploading, null otherwise.
  final double? progress;
  final String? error;
  final bool done;

  bool get uploading => progress != null;
}

/// Edits one content item: authoring of segments and questions, media upload
/// per key, and approval (which the server refuses while media is missing).
class ContentEditorController extends SafeChangeNotifier {
  ContentEditorController(
    this._repository,
    this._picker,
    this.studyId, {
    ContentDetail? initial,
    required this.canEdit,
  }) {
    if (initial == null) {
      _segments.add(SegmentDraft(uid: _uid++, id: 's1'));
      startSegment = 's1';
    } else {
      _fill(initial);
    }
  }

  /// Files above this size are refused before the upload starts.
  static const maxMediaBytes = 200 * 1024 * 1024;

  static const _accepted = {
    'video/webm',
    'video/mp4',
    'image/png',
    'image/jpeg',
  };

  final ContentRepository _repository;
  final MediaPicker _picker;
  final int studyId;
  final bool canEdit;

  int _uid = 0;
  String? _id;
  String _status = ContentStatus.draft;

  String title = '';
  final List<String> tags = [];
  String faceId = '';
  String voiceId = '';
  String startSegment = '';
  String postSegment = '';
  final List<SegmentDraft> _segments = [];
  final List<ComprehensionDraft> _comprehension = [];

  List<String> _missing = const [];
  List<String> _approveMissing = const [];
  final Map<String, MediaUploadState> _uploads = {};

  int revision = 0;
  bool _busy = false;
  bool _dirty = false;
  String? _error;
  String? _notice;

  String? get id => _id;
  String get status => _status;
  bool get isNew => _id == null;
  bool get isApproved => _status == ContentStatus.approved;
  bool get readOnly => !canEdit || isApproved;
  bool get busy => _busy;
  bool get dirty => _dirty;
  String? get error => _error;
  String? get notice => _notice;
  List<SegmentDraft> get segments => List.unmodifiable(_segments);
  List<ComprehensionDraft> get comprehension => List.unmodifiable(_comprehension);

  /// Media keys the server says have no upload yet.
  List<String> get missingMedia => _missing;

  /// What the server listed as missing when approval was refused.
  List<String> get approveMissing => _approveMissing;

  /// The distinct media keys of the segments, in order.
  List<String> get mediaKeys => [
        for (final k in {
          for (final s in _segments)
            if (s.mediaKey.trim().isNotEmpty) s.mediaKey.trim(),
        })
          k,
      ];

  MediaUploadState uploadOf(String key) =>
      _uploads[key] ?? const MediaUploadState();

  bool isMissing(String key) => _missing.contains(key) || isNew;

  /// Segment ids typed so far.
  List<String> get segmentIds => [
        for (final s in _segments)
          if (s.id.trim().isNotEmpty) s.id.trim(),
      ];

  void _fill(ContentDetail d) {
    _id = d.summary.id;
    _status = d.summary.status;
    title = d.summary.title;
    tags
      ..clear()
      ..addAll(d.summary.topicTags);
    faceId = d.summary.faceId;
    voiceId = d.summary.voiceId;
    startSegment = d.definition.startSegment;
    postSegment = d.definition.postSegment ?? '';
    _segments
      ..clear()
      ..addAll([
        for (final s in d.definition.segments) SegmentDraft.from(_uid++, s),
      ]);
    _comprehension
      ..clear()
      ..addAll([
        for (final c in d.definition.comprehension)
          ComprehensionDraft.from(_uid++, c),
      ]);
    _missing = d.summary.missingMedia;
    _dirty = false;
    revision++;
  }

  // ------------------------------------------------------------ editing

  void edit(void Function() change) {
    if (readOnly) return;
    change();
    _dirty = true;
    _error = null;
    _notice = null;
    _approveMissing = const [];
    notifyListeners();
  }

  void addTag(String text) => edit(() {
        final tag = text.trim();
        if (tag.isNotEmpty && !tags.contains(tag)) tags.add(tag);
      });

  void removeTag(String tag) => edit(() => tags.remove(tag));

  void addSegment() => edit(() {
        var n = _segments.length + 1;
        while (segmentIds.contains('s$n')) {
          n++;
        }
        _segments.add(SegmentDraft(uid: _uid++, id: 's$n'));
        if (startSegment.isEmpty) startSegment = 's$n';
      });

  void removeSegment(int uid) => edit(() {
        _segments.removeWhere((s) => s.uid == uid);
        if (!segmentIds.contains(startSegment)) {
          startSegment = segmentIds.isEmpty ? '' : segmentIds.first;
        }
        if (!segmentIds.contains(postSegment)) postSegment = '';
      });

  void addComprehension() => edit(() {
        _comprehension.add(ComprehensionDraft(uid: _uid++, id: 'c${_comprehension.length + 1}'));
      });

  void removeComprehension(int uid) =>
      edit(() => _comprehension.removeWhere((c) => c.uid == uid));

  // ------------------------------------------------------------ building

  List<double>? _numbers(String text, int count) {
    final parts = [
      for (final p in text.split(RegExp(r'[,\s]+')))
        if (p.trim().isNotEmpty) p.trim(),
    ];
    if (parts.length != count) return null;
    final values = [for (final p in parts) double.tryParse(p.replaceAll(',', '.'))];
    return values.contains(null) ? null : [for (final v in values) v!];
  }

  ContentDefinition? _definition() {
    final segments = <ContentSegment>[];
    for (final s in _segments) {
      final name = s.id.trim().isEmpty ? 'A segment' : 'Segment ${s.id.trim()}';
      final duration = double.tryParse(s.duration.trim().replaceAll(',', '.'));
      if (duration == null) {
        _error = '$name: the duration must be a number of seconds.';
        return null;
      }
      NormalizedFaceLayout? layout;
      final texts = [s.faceBox, s.eyeRegion, s.mouthRegion];
      if (texts.any((t) => t.trim().isNotEmpty)) {
        final boxes = <Box>[];
        const names = ['face box', 'eye region', 'mouth region'];
        for (var i = 0; i < 3; i++) {
          final n = _numbers(texts[i], 4);
          if (n == null) {
            _error = '$name: the ${names[i]} needs four numbers, for example '
                '0.3, 0.1, 0.4, 0.8.';
            return null;
          }
          boxes.add(Box(n[0], n[1], n[2], n[3]));
        }
        layout = NormalizedFaceLayout(
          faceBox: boxes[0],
          eyeRegion: boxes[1],
          mouthRegion: boxes[2],
        );
      }
      ContentQuestion? question;
      if (s.questionPrompt.trim().isNotEmpty || s.optionText.trim().isNotEmpty) {
        final parsed = parseOptionLines(s.optionText);
        question = ContentQuestion(
          id: s.questionId.trim().isEmpty ? 'q_${s.id.trim()}' : s.questionId.trim(),
          prompt: s.questionPrompt.trim(),
          options: parsed.options,
          branches: parsed.branches,
        );
      }
      segments.add(ContentSegment(
        id: s.id.trim(),
        text: s.text,
        mediaKey: s.mediaKey.trim(),
        durationS: duration,
        faceLayout: layout,
        question: question,
      ));
    }
    return ContentDefinition(
      startSegment: startSegment.trim(),
      postSegment: postSegment.trim().isEmpty ? null : postSegment.trim(),
      segments: segments,
      comprehension: [
        for (final c in _comprehension)
          ComprehensionItem(
            id: c.id.trim(),
            prompt: c.prompt.trim(),
            options: parseOptionLines(c.optionText).options,
            correct: c.correct.trim(),
          ),
      ],
    );
  }

  // ------------------------------------------------------------ actions

  Future<bool> save() async {
    if (readOnly || _busy) return false;
    _error = null;
    _notice = null;
    _approveMissing = const [];
    if (title.trim().isEmpty) {
      _error = 'Give the content a title.';
      notifyListeners();
      return false;
    }
    final def = _definition();
    if (def == null) {
      notifyListeners();
      return false;
    }
    _busy = true;
    notifyListeners();
    try {
      final saved = _id == null
          ? await _repository.create(
              studyId,
              title: title.trim(),
              topicTags: List.of(tags),
              faceId: faceId.trim(),
              voiceId: voiceId.trim(),
              definition: def,
            )
          : await _repository.update(
              studyId,
              _id!,
              title: title.trim(),
              topicTags: List.of(tags),
              faceId: faceId.trim(),
              voiceId: voiceId.trim(),
              definition: def,
            );
      _fill(saved);
      _notice = 'Draft saved.';
      return true;
    } catch (e) {
      _error = userMessage(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Lets the researcher pick a file for [key] and uploads it. The draft is
  /// saved first so the server knows the item.
  Future<void> uploadMedia(String key) async {
    if (readOnly || _busy || uploadOf(key).uploading) return;
    if (_id == null || _dirty) {
      if (!await save()) return;
    }
    final PickedMedia? file;
    try {
      file = await _picker.pick(accept: kAcceptedMedia);
    } catch (_) {
      _setUpload(key, const MediaUploadState(error: 'The file dialog could not be opened.'));
      return;
    }
    if (file == null) return;
    final type = file.contentType.isEmpty
        ? mediaTypeForName(file.name)
        : file.contentType;
    if (!_accepted.contains(type)) {
      _setUpload(key, const MediaUploadState(
        error: 'Use a WebM or MP4 video, or a PNG or JPEG image.',
      ));
      return;
    }
    if (file.bytes.length > maxMediaBytes) {
      _setUpload(key, const MediaUploadState(error: 'The file is larger than 200 MB.'));
      return;
    }
    _setUpload(key, const MediaUploadState(progress: 0));
    try {
      await _repository.uploadMedia(
        studyId,
        _id!,
        key,
        bytes: Uint8List.fromList(file.bytes),
        filename: file.name,
        contentType: type,
        onProgress: (sent, total) {
          final p = total == 0 ? 1.0 : (sent / total).clamp(0.0, 1.0);
          final now = uploadOf(key).progress ?? 0;
          // Repaint at whole percents only.
          if ((p * 100).floor() != (now * 100).floor()) {
            _setUpload(key, MediaUploadState(progress: p));
          }
        },
      );
      _missing = [
        for (final m in _missing)
          if (m != key) m,
      ];
      _approveMissing = [
        for (final m in _approveMissing)
          if (m != key) m,
      ];
      _setUpload(key, const MediaUploadState(done: true));
    } catch (e) {
      _setUpload(key, MediaUploadState(error: userMessage(e)));
    }
  }

  void _setUpload(String key, MediaUploadState state) {
    _uploads[key] = state;
    notifyListeners();
  }

  /// Approves the item. When the server names missing media (422) they are
  /// listed in [approveMissing].
  Future<bool> approve() async {
    if (readOnly || _busy) return false;
    if (_id == null || _dirty) {
      if (!await save()) return false;
    }
    _busy = true;
    _error = null;
    _notice = null;
    _approveMissing = const [];
    notifyListeners();
    try {
      final approved = await _repository.approve(studyId, _id!);
      _fill(approved);
      _notice = 'Content approved. It can now be attached to assignments.';
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      if (e.statusCode == 422) {
        final listed = e.missingMedia;
        _approveMissing = listed.isNotEmpty ? listed : _missing;
      }
      return false;
    } catch (e) {
      _error = userMessage(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }

  void dismissNotice() {
    _notice = null;
    notifyListeners();
  }
}
