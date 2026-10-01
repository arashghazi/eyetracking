import 'dart:async';

import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/live_repository.dart';
import 'segment_recorder.dart';

/// Where the live conversation stands.
enum LivePhase {
  /// Asking the server where the conversation stands.
  loading,

  /// The choice card: type or speak, keep a written record or not.
  choose,

  /// The conversation is open: the avatar talks, the participant answers.
  conversation,

  /// The conversation is over (any end reason); the closing line is on the
  /// screen until the participant continues.
  ended,

  /// The prompt-free post observation: the avatar plays again, nothing is
  /// asked.
  post,

  /// Nothing more to do here.
  finished,
}

/// A recording shorter than this is thrown away (a tap, not speech).
const Duration kShortestSpeech = Duration(milliseconds: 300);

/// Runs the live conversation with the avatar: loads where it stands, starts
/// it with the participant's choices, sends typed or spoken turns, shows the
/// caption and speaks each avatar line, offers a break after a distress
/// signal, closes it, and later plays the post observation.
///
/// The avatar video is drawn by a [VideoStageBuilder] widget that reports
/// back through [onVideoPlaying], [onVideoRect] and [onVideoError]; the
/// controller maps the protocol's normalized face layout onto the rectangle
/// the picture occupies and hands it to the [SegmentRecorder], exactly as the
/// interest practice does for its videos.
///
/// Nothing is kept of the participant's voice: a recording is held in memory
/// only until it is uploaded, and every microphone track is released after
/// each clip.
class LivePracticeController extends SafeChangeNotifier {
  LivePracticeController({
    required this.sessionId,
    required LiveRepository repository,
    required this._recorder,
    required this._screen,
    required this._speech,
    this._audioRecorder,
    this.closingFallback = 'Thank you for talking with me.',
    this.onFinished,
    this.onPostFinished,
  }) : _repo = repository;

  final String sessionId;

  /// What the avatar says at the end when the server's closing turn comes
  /// without its text (a conversation whose transcript is not kept).
  final String closingFallback;

  /// The conversation is over and the participant continued.
  final void Function(PracticeEnd end)? onFinished;

  /// The post observation has run its time.
  final void Function()? onPostFinished;

  final LiveRepository _repo;
  final SegmentRecorder _recorder;
  final ScreenInfo Function() _screen;
  final SpeechSynthesizer _speech;
  final AudioRecorderFactory? _audioRecorder;
  AudioRecorder? _mic;

  LivePhase _phase = LivePhase.loading;
  LiveSnapshot? _snapshot;
  LiveStart? _start;
  LiveConversation? _conversation;
  LiveLimits _limits = const LiveLimits();

  // The choice card.
  LiveInputMode _mode = LiveInputMode.typed;
  bool _allowTranscript = false;

  // The conversation.
  List<LiveTurn> _turns = const [];
  String? _caption;
  String? _heard;
  int _turnsUsed = 0;
  int _turnsLeft = 0;
  String? _endReason;
  bool _voiceOn = true;
  bool _distress = false;
  bool _typing = true;
  String _draft = '';
  bool _busy = false;
  bool _recording = false;
  bool _startingMic = false;
  bool _stopWanted = false;
  String? _error;
  bool _conflict = false;
  String? _loadError;

  // Video and the recorded segment.
  Box? _videoRect;
  bool _videoStarted = false;
  bool _segmentOpen = false;
  bool _paused = false;
  String? _videoProblem;
  int _videoAttempt = 0;

  // The post observation.
  Duration _postDuration = Duration.zero;
  Timer? _postTimer;
  final Stopwatch _postWatch = Stopwatch();
  bool _postClockStarted = false;

  // ------------------------------------------------------------ getters

  LivePhase get phase => _phase;
  LiveSnapshot? get snapshot => _snapshot;
  LiveConversation? get conversation => _conversation;
  LiveLimits get limits => _limits;
  LiveAvatar? get avatar => _start?.avatar;
  bool get isOpen => _conversation?.isOpen ?? false;

  /// What the participant may choose before starting.
  bool get offersSpeech => _snapshot?.offersSpeech ?? false;
  bool get storeTranscriptOffered => _snapshot?.storeTranscriptOffered ?? false;
  LiveInputMode get mode => _mode;
  bool get allowTranscript => _allowTranscript;

  /// The avatar line to show as the caption, or null before the first.
  String? get caption => _caption;

  /// What the server understood the participant said or typed last.
  String? get heard => _heard;
  List<LiveTurn> get turns => _turns;
  int get turnsUsed => _turnsUsed;
  int get turnsLeft => _turnsLeft;
  String? get endReason => _endReason;
  bool get voiceOn => _voiceOn;

  /// The device can speak the lines (and the avatar relies on it).
  bool get canSpeak =>
      _speech.isAvailable && (_start?.avatar.usesBrowserVoice ?? true);

  /// A calm offer of a break is on the screen.
  bool get distress => _distress && _phase == LivePhase.conversation;

  /// A request is in flight: input is off until it is answered.
  bool get busy => _busy;
  bool get recording => _recording;

  /// The microphone is being asked for (a permission prompt may be open).
  bool get startingRecording => _startingMic;

  /// The conversation is a spoken one on a device that can record.
  bool get speechMode =>
      _conversation?.inputMode == LiveInputMode.speech && _micSupported;

  /// The text field is shown (always in a typed conversation; on request in
  /// a spoken one).
  bool get typing => _typing || !speechMode;

  /// What was typed and not sent yet. Kept here so a pause (which takes the
  /// screen away) does not lose it.
  String get draft => _draft;

  /// What went wrong, as the server wrote it (or a short sentence).
  String? get error => _error;

  /// The error is a 409: the conversation moved on, so offer "Reload".
  bool get conflict => _conflict;
  String? get loadError => _loadError;

  bool get canSend =>
      _phase == LivePhase.conversation && !_busy && !_recording && !_startingMic;

  /// The avatar video to play, or null when it should be off the screen.
  String? get videoUrl {
    if (_paused || _videoProblem != null) return null;
    final show = _phase == LivePhase.conversation ||
        _phase == LivePhase.ended ||
        _phase == LivePhase.post;
    return show ? _start?.avatar.videoUrl : null;
  }

  bool get videoMissing =>
      (_phase == LivePhase.conversation ||
          _phase == LivePhase.ended ||
          _phase == LivePhase.post) &&
      _start != null &&
      _start!.avatar.videoUrl == null;
  String? get videoProblem => _videoProblem;
  int get videoAttempt => _videoAttempt;
  Box? get videoRect => _videoRect;
  bool get paused => _paused;

  bool get _micSupported {
    final make = _audioRecorder;
    if (make == null) return false;
    return (_mic ??= make()).isSupported;
  }

  SessionSegmentName get _segment => _phase == LivePhase.post
      ? SessionSegmentName.post
      : SessionSegmentName.practice;

  // ------------------------------------------------------ load and start

  /// Asks the server where the conversation stands and shows the choice
  /// card, carries on an open conversation, or (when it already closed)
  /// finishes the practice.
  Future<void> load() async {
    _phase = LivePhase.loading;
    _loadError = null;
    notifyListeners();
    try {
      final snap = await _repo.snapshot(sessionId);
      _snapshot = snap;
      _limits = snap.limits;
      final c = snap.conversation;
      if (c == null) {
        _mode = LiveInputMode.typed;
        _phase = LivePhase.choose;
        notifyListeners();
        return;
      }
      if (c.isClosed) {
        _conversation = c;
        _turns = snap.turns;
        _endReason = c.endReason;
        _finishPractice();
        return;
      }
      // Open: the start call returns it again with the avatar and layout.
      await _begin(c.inputMode, c.transcriptAllowed, quietLoad: true);
    } catch (e) {
      _loadError = userMessage(e);
      notifyListeners();
    }
  }

  void chooseMode(LiveInputMode mode) {
    if (_phase != LivePhase.choose || _busy) return;
    if (mode == LiveInputMode.speech && !offersSpeech) return;
    _mode = mode;
    _error = null;
    notifyListeners();
  }

  void setAllowTranscript(bool value) {
    if (_phase != LivePhase.choose || _busy) return;
    _allowTranscript = value;
    notifyListeners();
  }

  /// "Start": opens the conversation with the choices made on the card.
  Future<void> begin() async {
    if (_phase != LivePhase.choose || _busy) return;
    await _begin(_mode, storeTranscriptOffered && _allowTranscript);
  }

  Future<void> _begin(
    LiveInputMode mode,
    bool allowTranscript, {
    bool quietLoad = false,
  }) async {
    _busy = true;
    _error = null;
    _conflict = false;
    notifyListeners();
    try {
      final s = await _repo.start(
        sessionId,
        mode: mode,
        allowTranscript: allowTranscript,
        tMs: _recorder.nowMs,
      );
      _applyStart(s);
    } catch (e) {
      if (quietLoad) {
        _loadError = userMessage(e);
      } else {
        _fail(e);
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _applyStart(LiveStart s) {
    _start = s;
    _conversation = s.conversation;
    _limits = s.limits;
    _turns = s.turns;
    _turnsUsed = s.conversation.turnsUsed;
    _turnsLeft = s.conversation.turnsLeft;
    _mode = s.conversation.inputMode;
    _typing = _mode == LiveInputMode.typed || !_micSupported;
    _caption = _lastText(s.turns, avatar: true);
    _heard = _lastText(s.turns, avatar: false);
    _distress = false;
    _loadError = null;
    if (s.conversation.isClosed) {
      _endReason = s.conversation.endReason;
      _phase = LivePhase.ended;
      return;
    }
    _phase = LivePhase.conversation;
    // A resumed conversation is not read out again from the top.
    if (!s.resumed) _speak(_caption);
  }

  static String? _lastText(List<LiveTurn> turns, {required bool avatar}) {
    for (final t in turns.reversed) {
      if (t.isAvatar == avatar && t.text != null && t.text!.isNotEmpty) {
        return t.text;
      }
    }
    return null;
  }

  // ------------------------------------------------------------- turns

  /// Sends a typed message. True when the server took it (the field can be
  /// cleared); false when it was not sent or was refused (the text stays).
  Future<bool> send(String text) async {
    final line = text.trim();
    if (line.isEmpty || !canSend) return false;
    if (line.length > _limits.maxParticipantChars) {
      _error = 'Please keep your message under '
          '${_limits.maxParticipantChars} characters.';
      _conflict = false;
      notifyListeners();
      return false;
    }
    _speech.cancel();
    return _sendTurn(
      () => _repo.sendTurn(
        sessionId,
        expectTurn: _turnsUsed,
        text: line,
        tMs: _recorder.nowMs,
      ),
      typed: line,
    );
  }

  Future<bool> _sendTurn(
    Future<LiveTurnResult> Function() request, {
    String? typed,
  }) async {
    _busy = true;
    _error = null;
    _conflict = false;
    notifyListeners();
    try {
      final r = await request();
      _applyTurn(r, typed: typed);
      return true;
    } catch (e) {
      _fail(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _applyTurn(LiveTurnResult r, {String? typed}) {
    final said = typed ?? r.participant?.text;
    _heard = said != null && said.isNotEmpty ? said : null;
    final avatarText = r.avatar.text ?? (r.done ? closingFallback : null);
    _turns = [
      ..._turns,
      if (r.participant != null) r.participant!,
      r.avatar,
    ];
    _turnsUsed = r.turnsUsed;
    _turnsLeft = r.turnsLeft;
    _caption = avatarText ?? _caption;
    _distress = r.distress;
    _speak(avatarText);
    if (r.done) _enterEnded(r.endReason);
  }

  void _enterEnded(String? reason) {
    _phase = LivePhase.ended;
    _endReason = reason;
    _distress = false;
    _turnsLeft = 0;
    final c = _conversation;
    if (c != null) {
      _conversation = LiveConversation(
        id: c.id,
        status: ConversationStatus.closed,
        topic: c.topic,
        inputMode: c.inputMode,
        transcriptAllowed: c.transcriptAllowed,
        turnsUsed: _turnsUsed,
        turnsLeft: 0,
        endReason: reason,
        startedAt: c.startedAt,
        endedAt: c.endedAt,
        providers: c.providers,
      );
    }
    unawaited(_releaseMic());
  }

  /// "End conversation".
  Future<void> endConversation() async {
    if (_phase != LivePhase.conversation || _busy) return;
    _speech.cancel();
    await _releaseMic();
    _busy = true;
    _error = null;
    _conflict = false;
    notifyListeners();
    try {
      final r = await _repo.end(sessionId, tMs: _recorder.nowMs);
      final text = r.avatar.text ?? closingFallback;
      _turns = [..._turns, r.avatar];
      _turnsUsed = r.turnsUsed;
      _caption = text;
      _speak(text);
      _enterEnded(r.endReason);
    } catch (e) {
      _fail(e);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// After the closing line: close the recorded segment and go on.
  Future<void> continueAfterEnd() async {
    if (_phase != LivePhase.ended) return;
    _speech.cancel();
    await _closeSegment();
    _finishPractice();
  }

  void _finishPractice() {
    if (_phase == LivePhase.finished) return;
    _phase = LivePhase.finished;
    notifyListeners();
    onFinished?.call(PracticeEnd.completed);
  }

  // ------------------------------------------------------ errors, reload

  void _fail(Object e) {
    _error = userMessage(e);
    _conflict = e is ApiException && e.statusCode == 409;
    notifyListeners();
  }

  /// Grows each time the message field should take the keyboard back, for
  /// example after a banner whose button had the focus goes away.
  int get inputFocusTicket => _inputFocusTicket;
  int _inputFocusTicket = 0;

  /// "Keep talking": the offer of a break goes away and typing can go on.
  void dismissDistress() {
    if (!_distress) return;
    _distress = false;
    _inputFocusTicket++;
    notifyListeners();
  }

  void dismissError() {
    if (_error == null) return;
    _error = null;
    _conflict = false;
    _inputFocusTicket++;
    notifyListeners();
  }

  /// Reads the conversation from the server again (after a 409) and carries
  /// on where it really is.
  Future<void> reload() async {
    if (_busy) return;
    _busy = true;
    _error = null;
    _conflict = false;
    notifyListeners();
    try {
      final snap = await _repo.snapshot(sessionId);
      _snapshot = snap;
      _limits = snap.limits;
      final c = snap.conversation;
      if (c == null) {
        _conversation = null;
        _phase = LivePhase.choose;
        return;
      }
      if (snap.turns.any((t) => t.text != null)) {
        _turns = snap.turns;
        _caption = _lastText(snap.turns, avatar: true) ?? _caption;
        _heard = _lastText(snap.turns, avatar: false);
      }
      _turnsUsed = c.turnsUsed;
      _turnsLeft = c.turnsLeft;
      _conversation = c;
      if (c.isClosed) {
        _caption ??= closingFallback;
        _enterEnded(c.endReason);
      } else {
        _phase = LivePhase.conversation;
      }
    } catch (e) {
      _fail(e);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------ voice, typing

  void toggleVoice() {
    _voiceOn = !_voiceOn;
    if (!_voiceOn) _speech.cancel();
    notifyListeners();
  }

  void _speak(String? text) {
    if (!_voiceOn || _paused || text == null || text.trim().isEmpty) return;
    _speech.speak(text);
  }

  /// The text field changed. Does not notify: the field shows what it holds.
  void setDraft(String value) => _draft = value;

  /// "Type instead": the text field in a spoken conversation.
  void typeInstead() {
    if (_phase != LivePhase.conversation) return;
    unawaited(_releaseMic());
    _typing = true;
    notifyListeners();
  }

  /// Back to the record button.
  void speakInstead() {
    if (_phase != LivePhase.conversation || !speechMode) return;
    _typing = false;
    notifyListeners();
  }

  // ------------------------------------------------------- recording

  /// Push to talk: asks for the microphone and starts recording. The record
  /// button calls it when pressed.
  Future<void> startRecording() async {
    if (!canSend || !speechMode || typing) return;
    final mic = _mic;
    if (mic == null || _recording || _startingMic) return;
    _speech.cancel();
    _startingMic = true;
    _stopWanted = false;
    _error = null;
    _conflict = false;
    notifyListeners();
    try {
      await mic.start(onLimit: _onRecordingLimit);
      _recording = true;
    } on AudioRecorderException catch (e) {
      _error = e.message;
      _typing = true;
      _stopWanted = false;
    } catch (_) {
      _error = 'The microphone could not be started. Type instead.';
      _typing = true;
      _stopWanted = false;
    } finally {
      _startingMic = false;
      notifyListeners();
    }
    // Let go before the microphone was ready: send what there is now.
    if (_recording && _stopWanted) {
      _stopWanted = false;
      await stopRecording();
    }
  }

  /// The recorder reached its longest clip and stopped by itself.
  void _onRecordingLimit() => unawaited(stopRecording());

  /// Ends the clip and sends it for turning into text.
  Future<void> stopRecording() async {
    if (_startingMic) {
      _stopWanted = true;
      return;
    }
    final mic = _mic;
    if (!_recording || mic == null) return;
    _recording = false;
    notifyListeners();
    AudioClip? clip;
    try {
      clip = await mic.stop();
    } catch (_) {
      clip = null;
    }
    if (clip == null || clip.duration < kShortestSpeech) {
      _error = 'We did not hear anything. Hold the button while you talk, '
          'or type instead.';
      _conflict = false;
      notifyListeners();
      return;
    }
    await _sendTurn(
      () => _repo.sendAudio(
        sessionId,
        expectTurn: _turnsUsed,
        clip: clip!,
        tMs: _recorder.nowMs,
      ),
    );
  }

  /// Throws a recording in progress away without sending it.
  Future<void> cancelRecording() async {
    if (!_recording && !_startingMic) return;
    _recording = false;
    _stopWanted = false;
    notifyListeners();
    await _releaseMic();
  }

  Future<void> _releaseMic() async {
    _recording = false;
    final mic = _mic;
    if (mic != null) {
      try {
        await mic.cancel();
      } catch (_) {}
    }
  }

  // --------------------------------------------------- video callbacks

  /// The player started (the picture is moving).
  void onVideoPlaying() {
    if (!_showsVideo) return;
    _videoStarted = true;
    unawaited(_openIfReady().then((_) => _startPostClock()));
  }

  /// The rectangle where the video is drawn changed (also the first time it
  /// is known). The layout is posted again so gaze samples are classified
  /// against the regions as they are on the screen now.
  void onVideoRect(Box rect) {
    _videoRect = rect;
    if (!_showsVideo) return;
    final layout = _layout();
    if (_segmentOpen && layout != null) {
      unawaited(_recorder.updateLayout(_segment, layout));
    } else {
      unawaited(_openIfReady());
    }
  }

  /// The video could not be loaded or played. The conversation goes on (it
  /// works without the picture); nothing is recorded for the gaze.
  void onVideoError(String message) {
    if (!_showsVideo || _videoProblem != null) return;
    unawaited(_closeSegment());
    _videoProblem = 'The avatar video could not be loaded.';
    notifyListeners();
    _startPostClock();
  }

  /// Tries the avatar video again.
  void retryVideo() {
    if (_videoProblem == null) return;
    _videoProblem = null;
    _videoStarted = false;
    _videoAttempt++;
    notifyListeners();
  }

  bool get _showsVideo =>
      _phase == LivePhase.conversation ||
      _phase == LivePhase.ended ||
      _phase == LivePhase.post;

  /// The layout of the face on the screen, or null when the protocol set no
  /// face layout or the video rectangle is not known yet.
  StimulusLayout? _layout() {
    final rect = _videoRect;
    final fl = _start?.faceLayout;
    if (rect == null || fl == null) return null;
    return fl.toStimulusLayout(_screen(), rect);
  }

  Future<void> _openIfReady() async {
    if (_segmentOpen || !_videoStarted || _paused || !_showsVideo) return;
    final layout = _layout();
    if (layout == null) return;
    _segmentOpen = true;
    try {
      await _recorder.openSegment(_segment, layout);
    } catch (e) {
      _segmentOpen = false;
      _error = userMessage(e);
      _conflict = false;
      notifyListeners();
    }
  }

  Future<void> _closeSegment() async {
    if (!_segmentOpen) return;
    _segmentOpen = false;
    try {
      await _recorder.closeSegment(_segment);
    } catch (e) {
      _error = userMessage(e);
      notifyListeners();
    }
  }

  // ---------------------------------------------------- post observation

  /// Plays the avatar once more for [duration], prompt-free: no caption, no
  /// voice, nothing asked. Records the post segment from the same layout.
  void startPost(Duration duration) {
    if (_phase == LivePhase.post) return;
    _speech.cancel();
    _postDuration = duration;
    _postClockStarted = false;
    _postWatch.reset();
    _phase = LivePhase.post;
    _paused = false;
    _videoStarted = false;
    _segmentOpen = false;
    _videoRect = null;
    _videoProblem = null;
    _videoAttempt++;
    notifyListeners();
    // Without a picture there is nothing to wait for.
    if (_start?.avatar.videoUrl == null) _startPostClock();
  }

  /// The clock of the post observation starts when the picture is moving
  /// (or, failing that, at once).
  void _startPostClock() {
    if (_phase != LivePhase.post || _postClockStarted || _paused) return;
    _postClockStarted = true;
    _postWatch.start();
    _schedulePost(_postDuration);
  }

  void _schedulePost(Duration remaining) {
    _postTimer?.cancel();
    _postTimer = Timer(remaining, () => unawaited(_postDone()));
  }

  Future<void> _postDone() async {
    if (_phase != LivePhase.post) return;
    _postTimer = null;
    _postWatch.stop();
    await _closeSegment();
    _phase = LivePhase.finished;
    notifyListeners();
    onPostFinished?.call();
  }

  // ------------------------------------------------------ pause / cancel

  /// The video comes off the screen, nothing is spoken and no recording
  /// goes on; the segment stays open on the server (the session is paused).
  void pause() {
    if (_paused) return;
    _paused = true;
    _distress = false;
    _speech.cancel();
    if (_recording || _startingMic) unawaited(cancelRecording());
    _holdPostClock();
    notifyListeners();
  }

  /// Plays the video again; the post observation carries on with what is
  /// left of its time.
  void resume() {
    if (!_paused) return;
    _paused = false;
    _videoStarted = false;
    _videoAttempt++;
    if (_phase == LivePhase.post && _postClockStarted) {
      final left = _postDuration - _postWatch.elapsed;
      _postWatch.start();
      _schedulePost(left.isNegative ? Duration.zero : left);
    }
    notifyListeners();
  }

  void _holdPostClock() {
    if (_phase == LivePhase.post && _postClockStarted) {
      _postWatch.stop();
      _postTimer?.cancel();
      _postTimer = null;
    }
  }

  /// The camera or screen changed: the segment on the server is closed and
  /// the video comes off the screen until [restartCurrent].
  void interrupted() {
    _segmentOpen = false;
    _paused = true;
    _speech.cancel();
    if (_recording || _startingMic) unawaited(cancelRecording());
    _holdPostClock();
    notifyListeners();
  }

  /// After a device change: the conversation (or the post observation) goes
  /// on, with the video playing again from the start.
  void restartCurrent() {
    _segmentOpen = false;
    _videoStarted = false;
    if (_paused) {
      _paused = false;
      _videoAttempt++;
      if (_phase == LivePhase.post && _postClockStarted) {
        final left = _postDuration - _postWatch.elapsed;
        _postWatch.start();
        _schedulePost(left.isNegative ? Duration.zero : left);
      }
    }
    notifyListeners();
  }

  /// Nothing more will be recorded or said (the session ended or was
  /// interrupted for good).
  void cancel() {
    _segmentOpen = false;
    _postTimer?.cancel();
    _postTimer = null;
    _speech.cancel();
    unawaited(_releaseMic());
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}
