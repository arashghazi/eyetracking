import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:participant_app/app.dart';

import 'fakes.dart';

/// Sets the logical test window size and restores it after the test.
void useWindow(WidgetTester tester, double width, [double height = 900]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps the app. With [signedIn] the fake account is already signed in.
Future<void> pumpApp(
  WidgetTester tester,
  TestBed bed, {
  bool signedIn = true,
}) async {
  if (signedIn) await bed.auth.signIn('sam@example.org', 'password1');
  await tester.pumpWidget(ParticipantApp(dependencies: bed.dependencies));
  await tester.pumpAndSettle();
}

/// Opens a step from the home screen.
Future<void> openStep(WidgetTester tester, String id) async {
  final button = find.byKey(Key('open-$id'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}
