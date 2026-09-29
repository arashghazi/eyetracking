import 'dart:math' as math;

import 'package:eyetracking_core/eyetracking_core.dart';

import 'number_placement.dart';

/// How the participant answers a trial.
enum TrialInput { number, fourChoice, symbol }

/// The four picture symbols of the symbol mode. `number_shown` is the name.
const List<String> kSymbolNames = ['circle', 'square', 'triangle', 'star'];

/// Resolves a stage's response mode against the participant's profile:
/// `profile` follows what they chose (keyboard and touch both mean number
/// entry).
TrialInput resolveTrialInput(StageResponseMode stage, ResponseMode profile) =>
    switch (stage) {
      StageResponseMode.number => TrialInput.number,
      StageResponseMode.fourChoice => TrialInput.fourChoice,
      StageResponseMode.symbol => TrialInput.symbol,
      StageResponseMode.profile => switch (profile) {
          ResponseMode.fourChoice => TrialInput.fourChoice,
          ResponseMode.symbol => TrialInput.symbol,
          _ => TrialInput.number,
        },
    };

/// A random 1 or 2 digit number, different from [not] when possible.
String randomNumber(math.Random random, {String? not}) {
  for (var i = 0; i < 10; i++) {
    final n = 1 + random.nextInt(99);
    if ('$n' != not) return '$n';
  }
  return not == '7' ? '8' : '7';
}

/// Four different numbers of the same length that include [shown], in random
/// order.
List<String> fourChoiceOptions(String shown, math.Random random) {
  final oneDigit = shown.length <= 1;
  final pool = oneDigit
      ? [for (var n = 1; n <= 9; n++) '$n']
      : [for (var n = 10; n <= 99; n++) '$n'];
  pool.remove(shown);
  pool.shuffle(random);
  return [shown, ...pool.take(3)]..shuffle(random);
}

/// What the participant sees and must answer in one trial.
class TrialStimulus {
  const TrialStimulus({
    required this.input,
    required this.shown,
    required this.options,
    required this.placement,
  });

  final TrialInput input;

  /// The number, or the symbol name in symbol mode.
  final String shown;

  /// Choices for [TrialInput.fourChoice] and [TrialInput.symbol]; empty for
  /// number entry.
  final List<String> options;
  final NumberPlacement placement;
}

/// Builds one trial for [stage].
TrialStimulus buildTrial({
  required GradualStage stage,
  required TrialInput input,
  required StimulusLayout layout,
  required math.Random random,
  String? previous,
  double bottomInset = 0,
}) {
  final String shown;
  if (input == TrialInput.symbol) {
    final choices = kSymbolNames.where((s) => s != previous).toList();
    shown = choices[random.nextInt(choices.length)];
  } else {
    shown = randomNumber(random, not: previous);
  }
  final chars = input == TrialInput.symbol ? 2 : shown.length;
  return TrialStimulus(
    input: input,
    shown: shown,
    options: switch (input) {
      TrialInput.number => const [],
      TrialInput.fourChoice => fourChoiceOptions(shown, random),
      TrialInput.symbol => List.of(kSymbolNames),
    },
    placement: placeNumber(
      zone: stage.numberZone,
      layout: layout,
      chars: chars,
      random: random,
      bottomInset: bottomInset,
    ),
  );
}
