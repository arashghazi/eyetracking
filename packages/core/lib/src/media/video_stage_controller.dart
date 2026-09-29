/// Remote control for a [VideoStage]: seek, play, pause and playback speed.
///
/// The controller remembers what it was told, so commands issued before the
/// video is ready (or while another clip is loading) are applied once the
/// player reports the video is loaded. Without an attached player every
/// command is a no-op.
class VideoStageController {
  double? _seekSeconds;
  bool _playing = false;
  double _rate = 1;
  VideoStagePlayer? _player;

  /// The position last asked for, in seconds, if any.
  double? get requestedSeconds => _seekSeconds;
  bool get wantsPlaying => _playing;
  double get rate => _rate;
  bool get attached => _player != null;

  void seek(double seconds) {
    _seekSeconds = seconds < 0 ? 0 : seconds;
    _player?.seek(_seekSeconds!);
  }

  void play() {
    _playing = true;
    _player?.play();
  }

  void pause() {
    _playing = false;
    _player?.pause();
  }

  void setRate(double rate) {
    _rate = rate;
    _player?.setRate(rate);
  }

  /// Player side: connects the player that carries out the commands.
  void attach(VideoStagePlayer player) {
    _player = player;
  }

  void detach(VideoStagePlayer player) {
    if (identical(_player, player)) _player = null;
  }

  /// Player side: a clip has loaded, so apply what was asked for so far.
  void applyPending() {
    final player = _player;
    if (player == null) return;
    player.setRate(_rate);
    final seek = _seekSeconds;
    if (seek != null) player.seek(seek);
    if (_playing) {
      player.play();
    } else {
      player.pause();
    }
  }

  /// Forgets the position (a new clip starts from its beginning).
  void reset() {
    _seekSeconds = null;
  }
}

/// What a player must be able to do for a [VideoStageController].
abstract interface class VideoStagePlayer {
  void seek(double seconds);
  void play();
  void pause();
  void setRate(double rate);
}
