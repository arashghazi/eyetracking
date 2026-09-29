import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_admin/app.dart';

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
  String role = 'admin',
}) async {
  bed.authRepository.role = role;
  if (signedIn) await bed.auth.signIn('staff@example.org', 'password1');
  await tester.pumpWidget(ResearchAdminApp(dependencies: bed.dependencies));
  await tester.pumpAndSettle();
}

/// Signs in, opens the first study.
Future<void> openStudy(
  WidgetTester tester,
  TestBed bed, {
  String role = 'admin',
}) async {
  await pumpApp(tester, bed, role: role);
  await tester.tap(find.byKey(const Key('study-1')));
  await tester.pumpAndSettle();
}

Future<void> openTab(WidgetTester tester, String name) async {
  final tab = find.widgetWithText(Tab, name);
  await tester.ensureVisible(tab);
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

/// Records what the page copies to the clipboard.
List<String> captureClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

/// Scrolls the nearest scrollable so [finder] is on screen, then taps it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
