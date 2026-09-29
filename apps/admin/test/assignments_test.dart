import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'helpers.dart';

/// Opens participant P-001 of the first study.
Future<void> openParticipant(
  WidgetTester tester,
  TestBed bed, {
  String role = 'researcher',
}) async {
  await openStudy(tester, bed, role: role);
  await tester.tap(find.text('P-001'));
  await tester.pumpAndSettle();
}

/// Scrolls the lazily built detail page until [finder] exists, then reveals it.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String key, String label) async {
  await scrollTo(tester, find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(label).last);
  await tester.pumpAndSettle();
}

TestBed bedWith(List<Assignment> items) => TestBed(
      assignments: FakeAssignmentsRepository(items: items),
    );

void main() {
  group('Assignments in the participant detail', () {
    testWidgets('lists assignments with status, topic and content',
        (tester) async {
      useWindow(tester, 1000, 1400);
      await openParticipant(
        tester,
        bedWith([
          assignmentRow('1', AssignmentStatus.completed,
              order: 0,
              protocol: 'Faces v1',
              path: ProtocolPath.gradualFace),
          assignmentRow('2', AssignmentStatus.pendingTopic, order: 1),
          assignmentRow('3', AssignmentStatus.contentPending,
              order: 2, topic: 'trains'),
          assignmentRow('4', AssignmentStatus.ready,
              order: 3, topic: 'planes', contentTitle: 'Planes, part one'),
        ]),
      );
      await scrollTo(tester, find.byKey(const Key('assignments-section')));

      expect(find.text('Assignments'), findsOneWidget);
      expect(find.text('Faces v1 · version 1'), findsOneWidget);
      expect(find.text('Trains talk · version 1'), findsNWidgets(3));
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Topic needed'), findsOneWidget);
      expect(find.text('Content being prepared'), findsOneWidget);
      expect(find.text('Ready'), findsWidgets);
      expect(find.text('Topic: trains'), findsOneWidget);
      expect(find.text('Content: Planes, part one'), findsOneWidget);
      // Only the assignment that waits for content offers an attach.
      expect(find.byKey(const Key('attach-content-3')), findsOneWidget);
      expect(find.byKey(const Key('attach-content-4')), findsNothing);
      expect(find.byKey(const Key('attach-content-2')), findsNothing);
    });

    testWidgets('an empty list says so', (tester) async {
      useWindow(tester, 1000, 1400);
      await openParticipant(tester, TestBed());
      await scrollTo(tester, find.byKey(const Key('assignments-section')));
      expect(find.byKey(const Key('no-assignments')), findsOneWidget);
    });

    testWidgets('Assign protocol offers published protocols only and sends the '
        'order', (tester) async {
      useWindow(tester, 1000, 1400);
      final bed = TestBed();
      await openParticipant(tester, bed);
      await scrollTo(tester, find.byKey(const Key('assign-protocol')));

      // Nothing chosen: the button is disabled.
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('assign-submit'))).onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('assign-protocol')));
      await tester.pumpAndSettle();
      // Published: "Faces v1" and "Trains talk"; the draft is not offered.
      expect(find.textContaining('Faces v1 · version 1'), findsOneWidget);
      expect(find.textContaining('Trains talk · version 1'), findsOneWidget);
      expect(find.textContaining('Faces v2 draft'), findsNothing);
      await tester.tap(find.textContaining('Faces v1 · version 1'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('assign-order')), '2');
      await tester.pump();
      await tester.tap(find.byKey(const Key('assign-submit')));
      await tester.pumpAndSettle();

      expect(bed.assignments.created.single, (code: 'P-001', protocolId: '1', order: 2));
      expect(find.text('Protocol assigned.'), findsOneWidget);
      // The new assignment shows up in the list.
      expect(find.text('Faces v1 · version 1'), findsWidgets);
    });

    testWidgets('the order is optional', (tester) async {
      useWindow(tester, 1000, 1400);
      final bed = TestBed();
      await openParticipant(tester, bed);
      await choose(tester, 'assign-protocol', 'Trains talk');
      await tester.tap(find.byKey(const Key('assign-submit')));
      await tester.pumpAndSettle();
      expect(bed.assignments.created.single.order, isNull);
      expect(bed.assignments.created.single.protocolId, '3');
    });

    testWidgets('without a published protocol the section explains where to '
        'make one', (tester) async {
      useWindow(tester, 1000, 1400);
      final bed = TestBed(
        protocols: FakeProtocolsRepository(items: [
          ProtocolDetail(
            summary: protocolRow('2', 'Only a draft'),
            definition: ProtocolDefinition.starter(ProtocolPath.gradualFace),
          ),
        ]),
      );
      await openParticipant(tester, bed);
      await scrollTo(tester, find.byKey(const Key('no-published-protocols')));
      expect(find.byKey(const Key('assign-protocol')), findsNothing);
    });

    testWidgets('content_pending: approved content matching the topic comes '
        'first, then Attach content', (tester) async {
      useWindow(tester, 1000, 1400);
      final bed = TestBed(
        assignments: FakeAssignmentsRepository(items: [
          assignmentRow('3', AssignmentStatus.contentPending, topic: 'Space'),
        ]),
      );
      await openParticipant(tester, bed);
      await scrollTo(tester, find.byKey(const Key('attach-content-3')));

      // Attach is disabled until something is chosen.
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('attach-submit-3'))).onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('attach-content-3')));
      await tester.pumpAndSettle();

      // Approved items only ("Planes, draft" is a draft); the matching one
      // (tag "space" for topic "Space") is first and marked.
      expect(find.textContaining('Planes, draft'), findsNothing);
      final matching = find.text('Space, approved (matches topic)');
      final other = find.text('Trains, part one');
      expect(matching, findsOneWidget);
      expect(other, findsOneWidget);
      expect(tester.getTopLeft(matching).dy, lessThan(tester.getTopLeft(other).dy));

      await tester.tap(matching);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('attach-submit-3')));
      await tester.pumpAndSettle();

      expect(bed.assignments.attached.single, (id: '3', contentId: '3'));
      expect(find.text('Content attached. The participant can start now.'),
          findsOneWidget);
      // Now ready: the attach controls are gone.
      expect(find.byKey(const Key('attach-content-3')), findsNothing);
      expect(find.text('Content: Attached content'), findsOneWidget);
    });

    testWidgets('a topic that matches nothing lists content in the server order',
        (tester) async {
      useWindow(tester, 1000, 1400);
      final bed = TestBed(
        assignments: FakeAssignmentsRepository(items: [
          assignmentRow('3', AssignmentStatus.contentPending, topic: 'volcanoes'),
        ]),
      );
      await openParticipant(tester, bed);
      await scrollTo(tester, find.byKey(const Key('attach-content-3')));
      await tester.tap(find.byKey(const Key('attach-content-3')));
      await tester.pumpAndSettle();
      expect(find.textContaining('matches topic'), findsNothing);
      final first = find.text('Trains, part one');
      final second = find.text('Space, approved');
      expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));
    });

    testWidgets('no approved content: a note instead of a picker', (tester) async {
      useWindow(tester, 1000, 1400);
      final bed = TestBed(
        content: FakeContentRepository(items: []),
        assignments: FakeAssignmentsRepository(items: [
          assignmentRow('3', AssignmentStatus.contentPending, topic: 'trains'),
        ]),
      );
      await openParticipant(tester, bed);
      await scrollTo(tester, find.byKey(const Key('no-content-3')));
      expect(find.byKey(const Key('attach-content-3')), findsNothing);
    });

    testWidgets('a server refusal is shown', (tester) async {
      useWindow(tester, 1000, 1400);
      final bed = TestBed(
        assignments: FakeAssignmentsRepository(items: [
          assignmentRow('3', AssignmentStatus.contentPending, topic: 'space'),
        ])
          ..failure = const ApiException(
            'content does not match the study',
            statusCode: 422,
          ),
      );
      await openParticipant(tester, bed);
      await choose(tester, 'attach-content-3', 'Space, approved');
      await tester.tap(find.byKey(const Key('attach-submit-3')));
      await tester.pumpAndSettle();
      expect(find.text('content does not match the study'), findsOneWidget);
    });

    testWidgets('an open assignment can be cancelled', (tester) async {
      useWindow(tester, 1000, 1400);
      final bed = bedWith([
        assignmentRow('2', AssignmentStatus.pendingTopic),
        assignmentRow('1', AssignmentStatus.completed, order: 1),
      ]);
      await openParticipant(tester, bed);
      await scrollTo(tester, find.byKey(const Key('cancel-assignment-2')));
      expect(find.byKey(const Key('cancel-assignment-1')), findsNothing,
          reason: 'a finished one cannot be cancelled');
      await tester.tap(find.byKey(const Key('cancel-assignment-2')));
      await tester.pumpAndSettle();
      expect(bed.assignments.cancelled, ['2']);
      expect(find.text('Assignment cancelled.'), findsOneWidget);
      expect(find.byKey(const Key('cancel-assignment-2')), findsNothing);
    });

    testWidgets('analysts only read', (tester) async {
      useWindow(tester, 1000, 1400);
      await openParticipant(
        tester,
        bedWith([
          assignmentRow('3', AssignmentStatus.contentPending, topic: 'trains'),
        ]),
        role: 'analyst',
      );
      await scrollTo(tester, find.byKey(const Key('assignments-section')));
      expect(find.text('Topic: trains'), findsOneWidget);
      expect(find.byKey(const Key('assign-protocol')), findsNothing);
      expect(find.byKey(const Key('attach-content-3')), findsNothing);
      expect(find.byKey(const Key('cancel-assignment-3')), findsNothing);
    });

    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('the section fits ${width.toInt()} px', (tester) async {
        useWindow(tester, width, width == 360 ? 740 : 900);
        await openParticipant(
          tester,
          bedWith([
            assignmentRow('3', AssignmentStatus.contentPending,
                order: 0, topic: 'a rather long topic name for a narrow phone'),
            assignmentRow('4', AssignmentStatus.ready, order: 1),
          ]),
        );
        await scrollTo(tester, find.byKey(const Key('attach-submit-3')));
        await scrollTo(tester, find.byKey(const Key('assign-submit')));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
