import 'dart:async';

import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/media_key.dart';
import '../domain/session_repository.dart';
import 'segment_recorder.dart';

/// The parts of the interest path.
enum InterestPart { conversation, comprehension, post }

/// What the interest practice shows right now.
enum InterestPhase {
  /// Not started.
  ready,

  /// A video segment is playing (or failed: see `videoProblem`).
  playing,

  /// The question at the end of a segment.
  question,

  /// A comprehension question.
  comprehension,

  /// Waiting for the server.
  posting,

  /// Conversation and comprehension are done (the post segment may follow).
  finished,
}

/// Runs the interest conversation: plays the personalized video segments,
/// asks the branching questions, then the comprehension questions, and later
/// plays the prompt-free post segment.
///
/// The video itself is drawn by a [VideoStageBuilder] widget that reports
/// back through [onVideoPlaying], [onVideoRect], [onVideoEnded] and
/// [onVideoError]; the controller maps the segment's normalized face layout
/// onto the rectangle the picture occupies and hands it to the
/// [SegmentRecorder].
class InterestPracticeController extends SafeChangeNotifier {
  InterestPracticeController({
    required this.sessionId,
    required this._content,
    required this._reloadContent,
    required SessionRepository repository,
    required this._recorder,
    required this._screen,
    this.showCaptions = false,
    this.onFinished,
    this.onPostFinished,
  }) : _repo = repository;

  final String sessionId;

  /// Personalized text is shown as captions only when the participant asked
  /// for captions in their profile.
  final bool showCaptions;

  /// Conversation and comprehension are over.
  final void Function(PracticeEnd end)? onFinished;

  /// The post segment has finished playing.
  final void Function()? onPostFinished;

  final SessionRepository _repo;
  final SegmentRecorder _recorder;
  final ScreenInfo Function() _screen;
  final Future<PersonalizedContent> Function() _reloadContent;

  PersonalizedContent _content;
  InterestPart _part = InterestPart.conversation;
  InterestPhase _phase = InterestPhase.ready;
  PersonalizedSegment? _segment;
  String? _lastConversationSegment;
  int _comprehensionIndex = 0;

  Box? _videoRect;
  bool _videoStarted = false;
  bool _mediaStartSent = false;
  bool _segmentOpen = false;
  String? _videoProblem;
  int _videoAttempt = 0;
  bool _reloading = false;
  bool _busy = false;
  String? _error;
  bool _finished = false;
  bool _paused = false;

  // ------------------------------------------------------------ getters

  PersonalizedContent get content => _content;
  InterestPart get part => _part;
  InterestPhase get phase => _phase;
  PersonalizedSegment? get segment => _segment;
  int get videoAttempt => _videoAttempt;

  /// "The video is not ready" when non-null.
  String? get videoProblem => _videoProblem;
  bool get reloading => _reloading;
  bool get busy => _busy;
  String? get error => _error;
  Box? get videoRect => _videoRect;

  /// The video that should be on the screen, or null.
  String? get videoUrl =>
      _phase == InterestPhase.playing && !_paused && _videoProblem == null
          ? _segment?.mediaUrl
          : null;

  /// The question waiting for an answer (interaction or comprehension).
  PersonalizedQuestion? get question => switch (_phase) {
        InterestPhase.question => _segment?.question,
        InterestPhase.comprehension =>
          _comprehensionIndex < _content.comprehension.length
              ? _content.comprehension[_comprehensionIndex]
              : null,
        _ => null,
      };

  int get comprehensionIndex => _comprehensionIndex;
  int get comprehensionCount => _content.comprehension.length;

  /// Caption under the video, only for participants who asked for captions.
  String? get caption {
    if (!showCaptions || _phase != InterestPhase.playing) return null;
    final text = _segment?.text.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  SessionSegmentName get _recordedSegment => _part == InterestPart.post
      ? SessionSegmentName.post
      : SessionSegmentName.practice;

  // ------------------------------------------------------------ control

  /// Starts the conversation with the start segment.
  void start() {
    if (_phase != InterestPhase.ready) return;
    final first = _content.segment(_content.startSegment);
    if (first == null) {
      _error = 'The conversation has no first segment.';
      notifyListeners();
      return;
    }
    _part = InterestPart.conversation;
    _play(first);
  }

  /// Plays the prompt-free post segment: the one the content names, or the
  /// last one played when it names none.
  void startPost() {
    _part = InterestPart.post;
    final seg = _content.segment(_content.postSegment) ??
        _content.segment(_lastConversationSegment) ??
        _content.segment(_content.startSegment);
    if (seg == null) {
      _error = 'There is no video for the post observation.';
      notifyListeners();
      return;
    }
    _play(seg);
  }

  void _play(PersonalizedSegment seg) {
    _segment = seg;
    _phase = InterestPhase.playing;
    _videoStarted = false;
    // A segment whose file was never uploaded has no URL to play.
    _videoProblem = seg.mediaUrl.isEmpty ? 'The video is not ready' : null;
    _mediaStartSent = false;
    _error = null;
    _videoAttempt++;
    if (_part == InterestPart.conversation) _lastConversationSegment = seg.id;
    notifyListeners();
  }

  // ------------------------------------------------- video callbacks

  /// The player started (the picture is moving).
  void onVideoPlaying() {
    if (_phase != InterestPhase.playing) return;
    _videoStarted = true;
    _announceMediaStart();
    unawaited(_openIfReady());
  }

  /// Tells the service that a clip started, once per play, so the researcher's
  /// replay can line the video up with the gaze. A failure here never stops
  /// the practice: it only costs the replay its video.
  void _announceMediaStart() {
    final seg = _segment;
    if (_mediaStartSent || seg == null) return;
    _mediaStartSent = true;
    unawaited(_repo
        .postEvent(
          sessionId,
          SessionEventType.mediaStart,
          tMs: _recorder.nowMs,
          payload: {
            'segment_id': seg.id,
            // The service's own key when it names one, else what the link
            // shows, else the segment id.
            'media_key': (seg.mediaKey != null && seg.mediaKey!.isNotEmpty)
                ? seg.mediaKey
                : mediaKeyFromUrl(seg.mediaUrl, seg.id),
          },
        )
        .then<void>((_) {}, onError: (Object _) {}));
  }

  /// The rectangle where the video is drawn changed (also the first time it
  /// is known). The layout is posted again so gaze samples are classified
  /// against the regions as they are on the screen now.
  void onVideoRect(Box rect) {
    _videoRect = rect;
    if (_phase != InterestPhase.playing) return;
    final layout = _layout();
    if (_segmentOpen && layout != null) {
      unawaited(_recorder.updateLayout(_recordedSegment, layout));
    } else {
      unawaited(_openIfReady());
    }
  }

  /// The layout of the current segment on the screen, or null when the
  /// segment has no face layout or the video rectangle is not known yet.
  StimulusLayout? _layout() {
    final rect = _videoRect;
    final fl = _segment?.faceLayout;
    if (rect == null || fl == null) return null;
    return fl.toStimulusLayout(_screen(), rect);
  }

  Future<void> _openIfReady() async {
    if (_segmentOpen || !_videoStarted || _paused) return;
    final layout = _layout();
    if (layout == null) return;
    _segmentOpen = true;
    try {
      await _recorder.openSegment(_recordedSegment, layout);
    } catch (e) {
      _segmentOpen = false;
      _error = userMessage(e);
      notifyListeners();
    }
  }

  /// The video played to its end.
  Future<void> onVideoEnded() async {
    if (_phase != InterestPhase.playing || _paused) return;
    final seg = _segment;
    await _closeSegment();
    if (seg == null) return;
    if (_part == InterestPart.post) {
      _phase = InterestPhase.finished;
      notifyListeners();
      onPostFinished?.call();
      return;
    }
    if (seg.question != null) {
      _phase = InterestPhase.question;
      notifyListeners();
    } else {
      _endConversation();
    }
  }

  /// The video could not be loaded or played.
  Future<void> onVideoError(String message) async {
    if (_phase != InterestPhase.playing || _videoProblem != null) return;
    await _closeSegment();
    _videoProblem = 'The video is not ready';
    notifyListeners();
  }

  Future<void> _closeSegment() async {
    if (!_segmentOpen) return;
    _segmentOpen = false;
    try {
      await _recorder.closeSegment(_recordedSegment);
    } catch (e) {
      _error = userMessage(e);
    }
  }

  /// Fetches the content again (its signed links may have expired) and plays
  /// the segment once more.
  Future<void> retryVideo() async {
    final seg = _segment;
    if (_videoProblem == null || seg == null || _reloading) return;
    _reloading = true;
    notifyListeners();
    try {
      _content = await _reloadContent();
    } catch (_) {
      // Keep the links we have; they may still work.
    }
    _reloading = false;
    _play(_content.segment(seg.id) ?? seg);
  }

  // ------------------------------------------------------- questions

  /// The participant chose [option] at the end of a segment.
  Future<void> answerInteraction(String option) async {
    final seg = _segment;
    final q = seg?.question;
    if (_phase != InterestPhase.question || seg == null || q == null || _busy) {
      return;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _repo.postAnswer(
        sessionId,
        AnswerRequest(
          segmentId: seg.id,
          questionId: q.id,
          kind: AnswerKind.interaction,
          option: option,
          tMs: _recorder.nowMs,
        ),
      );
      _busy = false;
      final next = _content.segment(result.nextSegmentId);
      if (next != null) {
        _play(next);
      } else {
        _endConversation();
      }
    } catch (e) {
      _busy = false;
      _error = userMessage(e);
      notifyListeners();
    }
  }

  void _endConversation() {
    if (_content.comprehension.isEmpty) {
      _finish();
      return;
    }
    _part = InterestPart.comprehension;
    _comprehensionIndex = 0;
    _phase = InterestPhase.comprehension;
    notifyListeners();
  }

  /// The participant answered the current comprehension question.
  Future<void> answerComprehension(String option) async {
    final q = question;
    if (_phase != InterestPhase.comprehension || q == null || _busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _repo.postAnswer(
        sessionId,
        AnswerRequest(
          segmentId: _lastConversationSegment ?? _content.startSegment,
          questionId: q.id,
          kind: AnswerKind.comprehension,
          option: option,
          tMs: _recorder.nowMs,
        ),
      );
      _busy = false;
      _comprehensionIndex++;
      if (_comprehensionIndex >= _content.comprehension.length) {
        _finish();
      } else {
        notifyListeners();
      }
    } catch (e) {
      _busy = false;
      _error = userMessage(e);
      notifyListeners();
    }
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _phase = InterestPhase.finished;
    notifyListeners();
    onFinished?.call(PracticeEnd.completed);
  }

  // ------------------------------------------------------ pause / cancel

  /// The video is taken off the screen; the segment stays open on the
  /// server (the session is paused).
  void pause() {
    if (_phase != InterestPhase.playing) return;
    _paused = true;
    notifyListeners();
  }

  /// Plays the current segment again from its start.
  void resume() {
    if (!_paused) return;
    _paused = false;
    final seg = _segment;
    if (_phase == InterestPhase.playing && seg != null) {
      _play(seg);
    } else {
      notifyListeners();
    }
  }

  /// The camera or screen changed: the segment on the server is closed and
  /// the video comes off the screen until [restartCurrent].
  void interrupted() {
    _segmentOpen = false;
    if (_phase == InterestPhase.playing) {
      _paused = true;
      notifyListeners();
    }
  }

  /// After a device change the segment is closed on the client side; the
  /// current segment is played again from the start.
  void restartCurrent() {
    _paused = false;
    _segmentOpen = false;
    final seg = _segment;
    if (_phase == InterestPhase.playing && seg != null) {
      _play(seg);
    } else {
      notifyListeners();
    }
  }

  /// Nothing more will be recorded (the session ended or was interrupted).
  void cancel() {
    _segmentOpen = false;
  }
}
