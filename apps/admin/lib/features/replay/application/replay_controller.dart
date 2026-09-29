import 'dart:async';

import 'package:eyetracking_core/eyetracking_core.dart';

import '../domain/replay_repository.dart';

/// Plays one session back: a position on the session clock that a play
/// button, a scrubber and the arrow keys move, and everything that is true
/// at that position (layout, gaze sample and trail, trial, gap, pause, the
/// stimulus clip).
///
/// The controller has no widgets and no timers of its own for playback: the
/// screen's ticker calls [advance], so tests can step time exactly. The
/// stimulus video is driven through a [VideoStageController]; its seeks are
/// limited to [maxSeeksPerSecond] because scrubbing would otherwise flood
/// the player.
class ReplayController extends SafeChangeNotifier {
  ReplayController(
    this._repository,
    this.studyId,
    this.sessionId, {
    VideoStageController? video,
    int Function()? clockMs,
    Timer Function(Duration, void Function())? schedule,
  })  : video = video ?? VideoStageController(),
        _clockMs = clockMs ?? _wallClockMs,
        _schedule = schedule ?? Timer.new;

  /// Keyboard and button step.
  static const stepMs = 100;

  /// How far back the fading gaze trail reaches.
  static const trailMs = 500;

  /// The playback speeds on offer.
  static const speeds = [0.5, 1.0, 2.0];

  /// Video seeks are limited to this many per second.
  static const maxSeeksPerSecond = 4;
  static const _minSeekGapMs = 1000 ~/ maxSeeksPerSecond;

  static int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;

  final ReplayRepository _repository;
  final int studyId;
  final String sessionId;

  /// The remote control of the stimulus video panel.
  final VideoStageController video;

  final int Function() _clockMs;
  final Timer Function(Duration, void Function()) _schedule;

  ReplayBundle? _bundle;
  bool _loading = false;
  String? _error;

  double _positionMs = 0;
  bool _playing = false;
  double _speed = 1;

  ReplayMedia? _syncedMedia;
  ReplayMedia? _stageMedia;
  int? _lastSeekAtMs;
  Timer? _seekTimer;
  int _videoSeeks = 0;

  // ------------------------------------------------------------ state

  ReplayBundle? get bundle => _bundle;
  bool get loading => _loading;
  String? get error => _error;

  /// Current position on the session clock.
  int get positionMs => _positionMs.floor();
  bool get playing => _playing;
  double get speed => _speed;
  int get durationMs => _bundle?.durationMs ?? 0;
  bool get atEnd => _bundle != null && positionMs >= durationMs;

  /// How many seeks were actually sent to the video player.
  int get videoSeeks => _videoSeeks;

  // ---------------------------------------------------- what is true now

  ReplayLayout? get activeLayout => _bundle?.layoutAt(positionMs);
  ReplaySegment? get activeSegment => _bundle?.segmentAt(positionMs);
  ReplayTrial? get activeTrial => _bundle?.trialAt(positionMs);
  TimeSpan? get activeGap => _bundle?.gapAt(positionMs);
  TimeSpan? get activePause => _bundle?.pauseAt(positionMs);

  /// The estimate at the current time, or null in a gap or before the first
  /// sample. A sample without x and y is returned too: it draws nothing.
  ReplaySample? get currentSample => _bundle?.sampleAt(positionMs);

  /// The samples of the last [trailMs] up to now that have a position,
  /// oldest first (the fading trail).
  List<ReplaySample> get trail {
    final b = _bundle;
    if (b == null) return const [];
    final now = positionMs;
    return [
      for (final s in b.samples.window(now - trailMs, now))
        if (s.hasPosition && b.gapAt(s.tMs) == null) s,
    ];
  }

  /// Name of the region of the current sample, or why there is none.
  String get regionText {
    final s = currentSample;
    if (s != null) return s.regionName;
    if (activeGap != null) return 'No samples (gap)';
    return '-';
  }

  /// The clip playing now, or null.
  ReplayMedia? get activeMedia => _bundle?.mediaAt(positionMs);

  /// The clip the stimulus panel shows: the one playing now, else the last
  /// one that played, else the first.
  ReplayMedia? get stageMedia {
    final b = _bundle;
    if (b == null || !b.hasMedia) return null;
    return activeMedia ?? _stageMedia ?? b.mediaEntries.first;
  }

  /// Seconds into the clip at the current position.
  double? get mediaSeconds {
    final m = activeMedia;
    return m == null ? null : (positionMs - m.startMs) / 1000;
  }

  // ------------------------------------------------------------ loading

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final bundle = await _repository.load(studyId, sessionId);
      _bundle = bundle;
      _positionMs = 0;
      _playing = false;
      _syncedMedia = null;
      _stageMedia = null;
      video
        ..reset()
        ..pause()
        ..setRate(_speed);
      _syncVideo(seek: true);
    } catch (e) {
      _error = userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void dismissError() {
    _error = null;
    notifyListeners();
  }

  // ------------------------------------------------------------ control

  void play() {
    final b = _bundle;
    if (b == null || _playing) return;
    if (positionMs >= b.durationMs) _positionMs = 0;
    _playing = true;
    _syncVideo(seek: true);
    notifyListeners();
  }

  void pause() {
    if (!_playing) return;
    _playing = false;
    _syncVideo(seek: false);
    notifyListeners();
  }

  void toggle() => _playing ? pause() : play();

  void setSpeed(double value) {
    if (!speeds.contains(value) || value == _speed) return;
    _speed = value;
    video.setRate(value);
    notifyListeners();
  }

  /// Jumps to [ms] (clamped to the session).
  void seek(int ms) {
    final b = _bundle;
    if (b == null) return;
    _positionMs = ms.clamp(0, b.durationMs).toDouble();
    _syncVideo(seek: true);
    notifyListeners();
  }

  /// Moves by [deltaMs] (negative goes back), as the arrow keys do.
  void step(int deltaMs) => seek(positionMs + deltaMs);

  /// Playback tick: moves the position by [elapsed] at the current speed and
  /// stops at the end.
  void advance(Duration elapsed) {
    final b = _bundle;
    if (b == null || !_playing) return;
    _positionMs += elapsed.inMicroseconds / 1000 * _speed;
    if (_positionMs >= b.durationMs) {
      _positionMs = b.durationMs.toDouble();
      _playing = false;
    }
    _syncVideo(seek: false);
    notifyListeners();
  }

  // ------------------------------------------------------- video sync

  /// Keeps the stimulus video in step with the timeline: a clip starts when
  /// the position enters it, pauses when the position leaves it or the
  /// timeline pauses, and follows the scrubber when [seek] is true.
  void _syncVideo({required bool seek}) {
    final media = activeMedia;
    if (media != null) _stageMedia = media;
    final entered = !identical(media, _syncedMedia);
    _syncedMedia = media;
    if (media == null) {
      video.pause();
      return;
    }
    if (entered || seek) _requestSeek();
    if (_playing) {
      video.play();
    } else {
      video.pause();
    }
  }

  /// Sends a seek to the video, at most [maxSeeksPerSecond] times a second;
  /// a request that comes too early is sent when the interval has passed,
  /// with the position as it is by then.
  void _requestSeek() {
    final now = _clockMs();
    final last = _lastSeekAtMs;
    if (last == null || now - last >= _minSeekGapMs) {
      _sendSeek(now);
      return;
    }
    _seekTimer ??= _schedule(Duration(milliseconds: _minSeekGapMs - (now - last)), () {
      _seekTimer = null;
      if (isDisposed) return;
      final seconds = mediaSeconds;
      if (seconds != null) _sendSeek(_clockMs(), seconds);
    });
  }

  void _sendSeek(int now, [double? seconds]) {
    final s = seconds ?? mediaSeconds;
    if (s == null) return;
    _lastSeekAtMs = now;
    _videoSeeks++;
    video.seek(s);
  }

  @override
  void dispose() {
    _seekTimer?.cancel();
    super.dispose();
  }
}
