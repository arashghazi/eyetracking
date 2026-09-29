import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'helpers.dart';

/// Every step screen must lay out at phone, tablet and desktop widths.
void main() {
  for (final width in [360.0, 800.0, 1440.0]) {
    for (final step in ['consent', 'demographics', 'profile']) {
      testWidgets('$step screen has no overflow at ${width.toInt()} px',
          (tester) async {
        useWindow(tester, width, 700);
        final bed = TestBed(home: FakeHomeRepository(reasons: const [
          ReadinessReason.consentMissingOrOutdated,
          ReadinessReason.demographicsIncomplete,
        ]));
        await pumpApp(tester, bed);
        await openStep(tester, step);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('sign-in has no overflow at ${width.toInt()} px', (tester) async {
      useWindow(tester, width, 640);
      await pumpApp(tester, TestBed(), signedIn: false);
      expect(tester.takeException(), isNull);
    });
  }
}
