import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('banner shows the message and can be dismissed', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: MessageBanner(message: 'Something failed', onDismiss: () => dismissed++),
      ),
    ));
    expect(find.text('Something failed'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    expect(dismissed, 1);
  });

  testWidgets('banner fits a 360 px wide screen with long text', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: MessageBanner(
          message: 'A long message ' * 20,
          onDismiss: () {},
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}
