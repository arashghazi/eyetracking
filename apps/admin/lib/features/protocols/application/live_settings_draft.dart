import 'package:eyetracking_core/eyetracking_core.dart';

/// An inclusive whole-number range with its default.
class LiveIntRange {
  const LiveIntRange(this.min, this.max, this.fallback);

  final int min;
  final int max;
  final int fallback;

  bool contains(int value) => value >= min && value <= max;
}

/// Ranges and limits the server enforces on the live section
/// (docs/api/step7-live-avatar.md).
abstract final class LiveRanges {
  static const maxTurns = LiveIntRange(1, 30, 8);
  static const maxMinutes = LiveIntRange(1, 30, 8);
  static const maxReplyWords = LiveIntRange(10, 80, 40);
  static const maxParticipantChars = LiveIntRange(50, 1000, 400);

  /// Longest scripted line.
  static const lineMaxChars = 400;

  /// Longest avatar or voice id.
  static const idMaxChars = 120;
}

/// A face layout to start from: the eye region sits above the mouth region.
const NormalizedFaceLayout kSampleFaceLayout = NormalizedFaceLayout(
  faceBox: Box(0.3, 0.1, 0.4, 0.8),
  eyeRegion: Box(0.3, 0.25, 0.4, 0.2),
  mouthRegion: Box(0.35, 0.55, 0.3, 0.2),
);

/// The three regions of the avatar's face layout.
enum FaceRegion {
  face('face', 'Face box'),
  eye('eye', 'Eye region'),
  mouth('mouth', 'Mouth region');

  const FaceRegion(this.key, this.label);

  /// Used in widget keys and error keys.
  final String key;
  final String label;
}

/// The four fractions of a box, in wire order.
const List<String> kBoxAxes = ['x', 'y', 'w', 'h'];
const Map<String, String> _axisNames = {
  'x': 'x',
  'y': 'y',
  'w': 'width',
  'h': 'height',
};

final RegExp _link = RegExp(r'(https?://|www\.)\S+', caseSensitive: false);
final RegExp _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');

double? _number(String text) {
  final v = double.tryParse(text.trim().replaceAll(',', '.'));
  return v != null && v.isFinite ? v : null;
}

String _box(Box? b) => b == null
    ? ''
    : [b.x, b.y, b.w, b.h].map(_fraction).join(' ');

String _fraction(double v) =>
    v == v.roundToDouble() ? '${v.round()}' : '$v';

/// What the researcher typed in the live section of the protocol editor.
///
/// Numbers stay text until the draft is built. [errors] mirrors what the
/// server checks, keyed by field, so a mistake shows next to its field; the
/// server still has the last word and its message is shown as written.
class LiveSettingsDraft {
  LiveSettingsDraft({LiveProtocolConfig config = const LiveProtocolConfig()})
      : maxTurns = '${config.maxTurns}',
        maxMinutes = '${config.maxMinutes}',
        maxReplyWords = '${config.maxReplyWords}',
        maxParticipantChars = '${config.maxParticipantChars}',
        openingLine = config.openingLine,
        closingLine = config.closingLine,
        redirectLine = config.redirectLine,
        distressLine = config.distressLine,
        avatarId = config.avatarId,
        voiceId = config.voiceId,
        typed = config.inputModes.contains(LiveInputMode.typed),
        speech = config.inputModes.contains(LiveInputMode.speech),
        storeTranscript = config.storeTranscript,
        useFaceLayout = config.faceLayout != null {
    final layout = config.faceLayout ?? kSampleFaceLayout;
    boxes = {
      FaceRegion.face: _split(_box(layout.faceBox)),
      FaceRegion.eye: _split(_box(layout.eyeRegion)),
      FaceRegion.mouth: _split(_box(layout.mouthRegion)),
    };
  }

  static List<String> _split(String text) => text.split(' ');

  String maxTurns;
  String maxMinutes;
  String maxReplyWords;
  String maxParticipantChars;
  String openingLine;
  String closingLine;
  String redirectLine;
  String distressLine;
  String avatarId;
  String voiceId;
  bool typed;
  bool speech;
  bool storeTranscript;
  bool useFaceLayout;

  /// Four texts (x, y, w, h) per region.
  late Map<FaceRegion, List<String>> boxes;

  // ------------------------------------------------------------ checking

  void _wholeNumber(
    Map<String, String> out,
    String key,
    String label,
    String text,
    LiveIntRange range,
  ) {
    final v = _number(text);
    if (v == null || v != v.roundToDouble() || !range.contains(v.round())) {
      out[key] = '$label must be a whole number from ${range.min} to '
          '${range.max}.';
    }
  }

  void _line(Map<String, String> out, String key, String label, String text) {
    if (text.trim().isEmpty) {
      out[key] = '$label is required (max ${LiveRanges.lineMaxChars} '
          'characters).';
    } else if (text.length > LiveRanges.lineMaxChars) {
      out[key] = '$label must be at most ${LiveRanges.lineMaxChars} '
          'characters.';
    } else if (_link.hasMatch(text) || _email.hasMatch(text)) {
      out[key] = '$label must not contain links or e-mail addresses.';
    }
  }

  void _id(Map<String, String> out, String key, String label, String text) {
    if (text.length > LiveRanges.idMaxChars) {
      out[key] = '$label must be at most ${LiveRanges.idMaxChars} characters.';
    }
  }

  /// The box typed for [region], or null while a number is missing.
  Box? boxOf(FaceRegion region) {
    final v = [for (final t in boxes[region]!) _number(t)];
    if (v.contains(null)) return null;
    return Box(v[0]!, v[1]!, v[2]!, v[3]!);
  }

  /// The eye region must lie above the mouth region.
  bool get faceRuleBroken {
    final eye = boxOf(FaceRegion.eye);
    final mouth = boxOf(FaceRegion.mouth);
    return eye != null && mouth != null && eye.bottom > mouth.y + 1e-6;
  }

  static const String faceRuleMessage =
      'The eye region must lie above the mouth region: its bottom edge '
      '(y + height) cannot be lower than the mouth region\'s top edge (y).';

  /// Every problem the server would refuse, by field key.
  Map<String, String> errors() {
    final out = <String, String>{};
    _wholeNumber(out, 'max-turns', 'Maximum turns', maxTurns, LiveRanges.maxTurns);
    _wholeNumber(
        out, 'max-minutes', 'Maximum minutes', maxMinutes, LiveRanges.maxMinutes);
    _wholeNumber(out, 'max-reply-words', 'Maximum reply words', maxReplyWords,
        LiveRanges.maxReplyWords);
    _wholeNumber(out, 'max-participant-chars', 'Maximum participant characters',
        maxParticipantChars, LiveRanges.maxParticipantChars);
    _line(out, 'opening-line', 'Opening line', openingLine);
    _line(out, 'closing-line', 'Closing line', closingLine);
    _line(out, 'redirect-line', 'Redirect line', redirectLine);
    _line(out, 'distress-line', 'Distress line', distressLine);
    _id(out, 'avatar-id', 'Avatar id', avatarId);
    _id(out, 'voice-id', 'Voice id', voiceId);
    if (!typed && !speech) {
      out['input-modes'] = 'Choose at least one input mode.';
    }
    if (useFaceLayout) {
      for (final region in FaceRegion.values) {
        for (var i = 0; i < 4; i++) {
          final v = _number(boxes[region]![i]);
          if (v == null || v < 0 || v > 1) {
            out['face-${region.key}-${kBoxAxes[i]}'] =
                '${region.label} ${_axisNames[kBoxAxes[i]]} must be a '
                'fraction from 0 to 1.';
          }
        }
      }
      if (faceRuleBroken) out['face-rule'] = faceRuleMessage;
    }
    return out;
  }

  /// The section as typed, or null while [errors] is not empty.
  LiveProtocolConfig? build() {
    if (errors().isNotEmpty) return null;
    return LiveProtocolConfig(
      maxTurns: _number(maxTurns)!.round(),
      maxMinutes: _number(maxMinutes)!.round(),
      maxReplyWords: _number(maxReplyWords)!.round(),
      maxParticipantChars: _number(maxParticipantChars)!.round(),
      openingLine: openingLine.trim(),
      closingLine: closingLine.trim(),
      redirectLine: redirectLine.trim(),
      distressLine: distressLine.trim(),
      avatarId: avatarId.trim(),
      voiceId: voiceId.trim(),
      inputModes: [
        if (typed) LiveInputMode.typed,
        if (speech) LiveInputMode.speech,
      ],
      storeTranscript: storeTranscript,
      faceLayout: useFaceLayout
          ? NormalizedFaceLayout(
              faceBox: boxOf(FaceRegion.face)!,
              eyeRegion: boxOf(FaceRegion.eye)!,
              mouthRegion: boxOf(FaceRegion.mouth)!,
            )
          : null,
    );
  }
}
