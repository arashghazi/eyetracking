/// Speaks a line aloud with the device's own voice (the live avatar's voice in
/// development). The browser implementation uses `window.speechSynthesis`;
/// elsewhere, and in tests, nothing is spoken.
///
/// Screens receive it as a dependency so tests can record what would have
/// been said.
abstract interface class SpeechSynthesizer {
  /// True when this device can speak. When false [speak] does nothing.
  bool get isAvailable;

  /// Speaks [text] now; a line that is still being spoken is cut off first.
  /// Never throws.
  void speak(String text);

  /// Stops whatever is being spoken. Never throws.
  void cancel();
}
