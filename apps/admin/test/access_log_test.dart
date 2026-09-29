import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'helpers.dart';

Future<void> openLog(WidgetTester tester, TestBed bed, {String role = 'researcher'}) async {
  await openStudy(tester, bed, role: role);
  await openTab(tester, 'Access log');
}

void main() {
  testWidgets('lists at, role, action and detail of every entry', (tester) async {
    useWindow(tester, 1440);
    final bed = TestBed();
    await openLog(tester, bed);

    expect(bed.accessLog.limits, [200]);
    final table = find.byKey(const Key('access-log-table'));
    expect(table, findsOneWidget);
    for (final header in ['At', 'Role', 'Action', 'Detail']) {
      expect(find.descendant(of: table, matching: find.text(header)), findsOneWidget);
    }
    expect(find.text('2026-09-30 09:15 UTC'), findsOneWidget);
    expect(find.text('researcher'), findsWidgets);
    expect(find.text('analyst'), findsOneWidget);
    expect(find.text('export_sessions'), findsOneWidget);
    expect(find.text('sessions.csv, 12 rows'), findsOneWidget);
    expect(find.text('session_id: 21'), findsOneWidget);
    expect(find.text('delete_participant_data'), findsOneWidget);
    expect(find.text('Latest 3'), findsOneWidget);
  });

  testWidgets('an object detail is shown as compact text', (tester) async {
    useWindow(tester, 800);
    final bed = TestBed(
      accessLog: FakeAccessLogRepository(entries: [
        AccessLogEntry.fromJson({
          'at': '2026-09-30T09:15:00',
          'role': 'admin',
          'action': 'reveal_identity',
          'detail': {'code': 'P-001', 'granted': true},
        }),
      ]),
    );
    await openLog(tester, bed, role: 'admin');
    expect(find.text('code: P-001, granted: true'), findsOneWidget);
    expect(find.text('reveal_identity'), findsOneWidget);
  });

  testWidgets('an empty log says so', (tester) async {
    useWindow(tester, 800);
    final bed = TestBed(accessLog: FakeAccessLogRepository(entries: const []));
    await openLog(tester, bed);
    expect(find.text('Nothing has been recorded yet.'), findsOneWidget);
  });

  testWidgets('a refusal shows the message and Reload tries again', (tester) async {
    useWindow(tester, 800);
    final repo = FakeAccessLogRepository()
      ..failure = const ApiException('You do not have permission to do this.',
          statusCode: 403);
    await openLog(tester, TestBed(accessLog: repo));
    expect(find.text('You do not have permission to do this.'), findsOneWidget);
    expect(find.text('The access log could not be loaded.'), findsOneWidget);

    repo.failure = null;
    await tester.tap(find.byKey(const Key('reload-access-log')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('access-log-table')), findsOneWidget);
  });

  for (final width in [360.0, 800.0, 1440.0]) {
    testWidgets('fits ${width.toInt()} px', (tester) async {
      useWindow(tester, width, width == 360 ? 740 : 900);
      await openLog(tester, TestBed());
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('access-log-table')), findsOneWidget);
    });
  }

  testWidgets('an administrator sees it too', (tester) async {
    useWindow(tester, 1440);
    await openLog(tester, TestBed(), role: 'admin');
    expect(find.byKey(const Key('access-log-table')), findsOneWidget);
  });
}
