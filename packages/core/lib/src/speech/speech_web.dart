// Web-only speech. Loaded through a conditional import, so it is never
// compiled for the VM or Android.
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'speech_synthesizer.dart';

/// Speaks with the browser's own voice (`window.speechSynthesis`), preferring
/// an English one. Browsers load their voices late, so the voice is chosen
/// each time a line is spoken; when none is listed yet the utterance asks for
/// English and the browser picks its default English voice.
class WebSpeechSynthesizer implements SpeechSynthesizer {
  /// Language asked for when no listed voice is chosen.
  static const language = 'en-US';

  @override
  bool get isAvailable {
    try {
      return web.window.has('speechSynthesis') &&
          web.window.has('SpeechSynthesisUtterance');
    } catch (_) {
      return false;
    }
  }

  @override
  void speak(String text) {
    final line = text.trim();
    if (line.isEmpty || !isAvailable) return;
    try {
      final synth = web.window.speechSynthesis;
      synth.cancel();
      final utterance = web.SpeechSynthesisUtterance(line)..lang = language;
      final voice = _englishVoice(synth);
      if (voice != null) {
        utterance
          ..voice = voice
          ..lang = voice.lang;
      }
      synth.speak(utterance);
    } catch (_) {
      // A voice that cannot speak must never stop the conversation.
    }
  }

  @override
  void cancel() {
    if (!isAvailable) return;
    try {
      web.window.speechSynthesis.cancel();
    } catch (_) {}
  }

  /// The first English voice, preferring US, then UK English.
  web.SpeechSynthesisVoice? _englishVoice(web.SpeechSynthesis synth) {
    final voices = synth.getVoices().toDart;
    web.SpeechSynthesisVoice? any;
    web.SpeechSynthesisVoice? uk;
    for (final v in voices) {
      final lang = v.lang.replaceAll('_', '-').toLowerCase();
      if (lang == 'en-us') return v;
      if (lang == 'en-gb') uk ??= v;
      if (lang == 'en' || lang.startsWith('en-')) any ??= v;
    }
    return uk ?? any;
  }
}

SpeechSynthesizer createSpeechSynthesizer() => WebSpeechSynthesizer();
