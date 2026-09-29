import 'dart:math' as math;

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:participant_app/features/session/domain/practice_trials.dart';

import 'practice_kit.dart';

void main() {
  test('random numbers have one or two digits and do not repeat back to back', () {
    final random = math.Random(4);
    String? previous;
    for (var i = 0; i < 300; i++) {
      final n = randomNumber(random, not: previous);
      expect(int.parse(n), inInclusiveRange(1, 99));
      expect(n.length, lessThanOrEqualTo(2));
      expect(n, isNot(previous));
      previous = n;
    }
  });

  test('four-choice options always include the shown number', () {
    final random = math.Random(9);
    for (var i = 0; i < 400; i++) {
      final shown = randomNumber(random);
      final options = fourChoiceOptions(shown, random);
      expect(options, hasLength(4));
      expect(options.toSet(), hasLength(4), reason: 'distinct options');
      expect(options, contains(shown));
      expect(options.every((o) => o.length == shown.length), isTrue,
          reason: 'same digit count as $shown');
    }
  });

  test('profile response mode decides when the stage says "profile"', () {
    TrialInput of(StageResponseMode s, ResponseMode p) => resolveTrialInput(s, p);
    expect(of(StageResponseMode.profile, ResponseMode.keyboard), TrialInput.number);
    expect(of(StageResponseMode.profile, ResponseMode.touch), TrialInput.number);
    expect(of(StageResponseMode.profile, ResponseMode.fourChoice), TrialInput.fourChoice);
    expect(of(StageResponseMode.profile, ResponseMode.symbol), TrialInput.symbol);
    // An explicit stage mode wins over the profile.
    expect(of(StageResponseMode.number, ResponseMode.symbol), TrialInput.number);
    expect(of(StageResponseMode.fourChoice, ResponseMode.touch), TrialInput.fourChoice);
    expect(of(StageResponseMode.symbol, ResponseMode.keyboard), TrialInput.symbol);
  });

  test('a symbol trial shows a symbol name and offers all four symbols', () {
    final layout = faceLayoutFor(screen1440);
    final random = math.Random(2);
    for (var i = 0; i < 50; i++) {
      final t = buildTrial(
        stage: const GradualStage(),
        input: TrialInput.symbol,
        layout: layout,
        random: random,
        bottomInset: 168,
      );
      expect(kSymbolNames, contains(t.shown));
      expect(t.options, unorderedEquals(kSymbolNames));
    }
  });

  test('a number trial has no options and a placement in the stage zone', () {
    final layout = faceLayoutFor(screen1440);
    final t = buildTrial(
      stage: const GradualStage(numberZone: NumberZone.nearEyes),
      input: TrialInput.number,
      layout: layout,
      random: math.Random(1),
      bottomInset: 168,
    );
    expect(t.options, isEmpty);
    expect(t.placement.zone, NumberZone.nearEyes);
    expect(int.tryParse(t.shown), isNotNull);
  });
}
