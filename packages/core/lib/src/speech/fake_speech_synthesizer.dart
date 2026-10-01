import 'speech_synthesizer.dart';

/// Records what would have been spoken. Import through `testing.dart`.
class FakeSpeechSynthesizer implements SpeechSynthesizer {
  FakeSpeechSynthesizer({this.available = true});

  bool available;

  /// Every line spoken, in order.
  final List<String> spoken = [];
  int cancelCount = 0;

  @override
  bool get isAvailable => available;

  @override
  void speak(String text) {
    if (available) spoken.add(text);
  }

  @override
  void cancel() => cancelCount++;
}
