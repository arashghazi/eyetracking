import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'helpers.dart';

void main() {
  testWidgets('profile edits are saved', (tester) async {
    useWindow(tester, 800, 1600);
    final bed = TestBed();
    await pumpApp(tester, bed);
    await openStep(tester, 'profile');

    // Loaded value is shown.
    expect(find.widgetWithText(TextField, 'Sam'), findsOneWidget);
    for (final label in ['Keyboard', 'Touch', 'Four choices', 'Symbols']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.byKey(const Key('response-keyboard')));
    await tester.pump();
    await tester.tap(find.text('Fast'));
    await tester.pump();

    // Free-text chip entry, confirmed with Enter.
    await tester.enterText(
      find.widgetWithText(TextField, 'For example: larger text'),
      'Larger text',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.widgetWithText(InputChip, 'Larger text'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'For example: trains'),
      'Trains',
    );
    await tester.tap(find.text('Add').last);
    await tester.pump();
    expect(find.widgetWithText(InputChip, 'Trains'), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();

    final saved = bed.profile.saved.single;
    expect(saved.displayName, 'Sam');
    expect(saved.responseMode, ResponseMode.keyboard);
    expect(saved.speed, Speed.fast);
    expect(saved.accessibilityNeeds, ['Larger text']);
    expect(saved.interests, ['Trains']);
    expect(find.text('Your profile has been saved.'), findsOneWidget);
  });
}
