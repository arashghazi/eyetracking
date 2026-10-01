import 'speech_synthesizer.dart';

/// Outside the browser nothing is spoken.
class StubSpeechSynthesizer implements SpeechSynthesizer {
  @override
  bool get isAvailable => false;

  @override
  void speak(String text) {}

  @override
  void cancel() {}
}

SpeechSynthesizer createSpeechSynthesizer() => StubSpeechSynthesizer();
