import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_admin/features/ai/application/ai_controller.dart';
import 'package:research_admin/features/ai/presentation/ai_widgets.dart';

import 'fakes.dart';
import 'helpers.dart';

Future<void> openAi(
  WidgetTester tester,
  TestBed bed, {
  String role = 'researcher',
}) async {
  await openStudy(tester, bed, role: role);
  await openTab(tester, 'AI');
}

Finder key(String k) => find.byKey(Key(k), skipOffstage: false);

Future<void> typeInto(WidgetTester tester, String k, String text) async {
  await tester.ensureVisible(key(k));
  await tester.pumpAndSettle();
  await tester.enterText(key(k), text);
  await tester.pump();
}

Future<void> tapKey(WidgetTester tester, String k) => tapVisible(tester, key(k));

String textOf(WidgetTester tester, String k) {
  final w = tester.widget<Text>(key(k));
  return w.data ?? w.textSpan!.toPlainText();
}

String plain(WidgetTester tester, String k) =>
    tester.widget<Text>(key(k)).textSpan!.toPlainText();

const _waiting = [
  ('1', AssignmentStatus.ready),
  ('2', AssignmentStatus.contentPending),
  ('3', AssignmentStatus.pendingTopic),
  ('4', AssignmentStatus.inProgress),
  ('5', AssignmentStatus.completed),
  ('6', AssignmentStatus.cancelled),
];

FakeAssignmentsRepository assignmentsFor() => FakeAssignmentsRepository(items: [
      for (final (id, status) in _waiting)
        assignmentRow(id, status, topic: status == AssignmentStatus.pendingTopic ? null : 'trains'),
    ]);

void main() {
  group('status card', () {
    testWidgets('shows configured providers, the model and the budget',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(ai: FakeAiRepository(status: configuredStatus));
      await openAi(tester, bed);

      expect(key('ai-status-card'), findsOneWidget);
      expect(textOf(tester, 'text-provider-name'), 'anthropic, claude-sonnet-x');
      expect(
        find.descendant(of: key('text-provider'), matching: find.text('Configured')),
        findsOneWidget,
      );
      expect(textOf(tester, 'video-provider-name'), 'heygen');
      expect(
        find.descendant(
            of: key('video-provider'), matching: find.text('Not configured')),
        findsOneWidget,
        reason: 'the video provider has no key on the server',
      );
      expect(find.text(SyntheticBadge.text), findsNothing);
      expect(plain(tester, 'budget-cap'), 'Cap 10.00');
      expect(plain(tester, 'budget-spent'), 'Spent 2.50');
      expect(plain(tester, 'budget-remaining'), 'Remaining 7.50');
      expect(textOf(tester, 'worker-state'), contains('every 30 s'));
      expect(find.textContaining('keys live on the server'), findsOneWidget);
      expect(find.textContaining('estimate in USD units'), findsOneWidget);
    });

    testWidgets('marks a development provider and its sample content',
        (tester) async {
      useWindow(tester, 1440, 2600);
      await openAi(tester, TestBed());
      expect(find.text(SyntheticBadge.text), findsNWidgets(2));
      expect(key('text-provider-synthetic'), findsOneWidget);
      expect(key('video-provider-synthetic'), findsOneWidget);
      expect(
        find.descendant(of: key('text-provider'), matching: find.text('Configured')),
        findsOneWidget,
      );
      expect(textOf(tester, 'worker-state'), startsWith('Off'));
      expect(plain(tester, 'budget-cap'), 'Cap 0.00');
      expect(find.textContaining('The cap is 0'), findsOneWidget);
    });

    testWidgets('a provider without a key says Not configured', (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(
        ai: FakeAiRepository(
          status: const AiStatus(
            textProvider: AiProviderStatus(name: 'anthropic', model: 'm'),
            videoProvider: AiProviderStatus(name: 'heygen'),
          ),
        ),
      );
      await openAi(tester, bed);
      expect(find.text('Not configured'), findsNWidgets(2));
      expect(find.text('Configured'), findsNothing);
    });

    testWidgets('researchers cannot edit the cap; administrators can',
        (tester) async {
      useWindow(tester, 1440, 2600);
      await openAi(tester, TestBed(ai: FakeAiRepository(status: configuredStatus)));
      expect(key('edit-cap'), findsNothing);
      expect(key('cap-field'), findsNothing);
    });

    testWidgets('analysts cannot edit the cap either', (tester) async {
      useWindow(tester, 1440, 2600);
      await openAi(tester, TestBed(), role: 'analyst');
      expect(key('edit-cap'), findsNothing);
    });

    testWidgets('an administrator sets the cap and sees the new figures',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(ai: FakeAiRepository(status: configuredStatus));
      await openAi(tester, bed, role: 'admin');

      await tapKey(tester, 'edit-cap');
      expect(tester.widget<TextField>(key('cap-field')).controller!.text, '10.00');
      await typeInto(tester, 'cap-field', '25.5');
      await tapKey(tester, 'save-cap');

      expect(bed.ai.budgetChanges, [25.5]);
      expect(key('cap-field'), findsNothing);
      expect(plain(tester, 'budget-cap'), 'Cap 25.50');
      expect(plain(tester, 'budget-remaining'), 'Remaining 23.00');
    });

    testWidgets('the server refusal of a cap is shown as written',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(ai: FakeAiRepository(status: configuredStatus))
        ..ai.budgetFailure = const ApiException(
          'cost_cap_units must not be lower than the amount already spent',
          statusCode: 422,
        );
      await openAi(tester, bed, role: 'admin');

      await tapKey(tester, 'edit-cap');
      await typeInto(tester, 'cap-field', '1');
      await tapKey(tester, 'save-cap');

      expect(
        find.descendant(
          of: key('budget-error'),
          matching: find.text(
              'cost_cap_units must not be lower than the amount already spent'),
        ),
        findsOneWidget,
      );
      expect(key('cap-field'), findsOneWidget, reason: 'the editor stays open');
      expect(plain(tester, 'budget-cap'), 'Cap 10.00');
    });

    testWidgets('a cap that is not a number is refused before the request',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(ai: FakeAiRepository(status: configuredStatus));
      await openAi(tester, bed, role: 'admin');
      await tapKey(tester, 'edit-cap');
      await typeInto(tester, 'cap-field', 'lots');
      await tapKey(tester, 'save-cap');
      expect(bed.ai.budgetChanges, isEmpty);
      expect(find.textContaining('Enter the cap as a number'), findsOneWidget);
    });

    testWidgets('a status that cannot be loaded says so in a banner',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed()
        ..ai.statusFailure = const ApiException('You are not a member of this study.',
            statusCode: 403);
      await openAi(tester, bed);
      expect(find.text('You are not a member of this study.'), findsOneWidget);
      expect(key('ai-status-missing'), findsOneWidget);
    });

    testWidgets(
        'an administrator without membership can still set the cap; a researcher sees nothing to edit',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed()
        ..ai.statusFailure =
            const ApiException('no access to this study', statusCode: 403);
      await openAi(tester, bed, role: 'admin');
      expect(key('ai-status-missing'), findsOneWidget);
      await tapKey(tester, 'edit-cap');
      expect(tester.widget<TextField>(key('cap-field')).controller!.text, '',
          reason: 'the current cap is unknown');
      await typeInto(tester, 'cap-field', '3');
      await tapKey(tester, 'save-cap');
      expect(bed.ai.budgetChanges, [3.0]);
      expect(textOf(tester, 'cap-saved'), 'Cost cap saved: 3.00 units.');
      expect(key('ai-status-missing'), findsOneWidget,
          reason: 'no status was invented from the answer');

      final other = TestBed()
        ..ai.statusFailure =
            const ApiException('no access to this study', statusCode: 403);
      await tester.pumpWidget(const SizedBox());
      await openAi(tester, other);
      expect(key('ai-status-missing'), findsOneWidget);
      expect(key('edit-cap'), findsNothing);
    });
  });

  group('text job form', () {
    testWidgets('assignment mode lists only content_pending and pending_topic',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(assignments: assignmentsFor());
      await openAi(tester, bed);

      // The default mode is "For an assignment".
      expect(key('job-participant-code'), findsOneWidget);
      expect(key('job-topic'), findsNothing);
      await typeInto(tester, 'job-participant-code', 'P-001');
      await tapKey(tester, 'find-assignments');

      expect(bed.assignments.listedCodes, ['P-001']);
      expect(key('job-assignment-2'), findsOneWidget);
      expect(key('job-assignment-3'), findsOneWidget);
      for (final id in ['1', '4', '5', '6']) {
        expect(key('job-assignment-$id'), findsNothing, reason: 'assignment $id');
      }
      expect(find.textContaining('Content being prepared'), findsOneWidget);
      expect(find.textContaining('Topic needed'), findsOneWidget);
    });

    testWidgets('a picked assignment is sent by id and nothing else is prefilled',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(assignments: assignmentsFor());
      await openAi(tester, bed);

      await typeInto(tester, 'job-participant-code', 'P-001');
      await tapKey(tester, 'find-assignments');
      // Nothing is chosen until the researcher picks one.
      await tapKey(tester, 'generate-text');
      expect(bed.ai.textRequests, isEmpty);
      expect(find.text('Choose an assignment.'), findsOneWidget);

      await tapKey(tester, 'job-assignment-3');
      await typeInto(tester, 'job-title', 'For P-001');
      await tapKey(tester, 'generate-text');

      expect(bed.ai.textRequests, hasLength(1));
      expect(bed.ai.textRequests.single.toJson(), {
        'assignment_id': 3,
        'interaction_points': 2,
        'length_seconds': 90,
        'title': 'For P-001',
      });
      expect(key('text-job-notice'), findsOneWidget);
    });

    testWidgets('the new job appears at the top of the jobs table',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(
        ai: FakeAiRepository(jobs: [
          aiJob('1', status: AiJobStatus.succeeded),
          aiJob('2', status: AiJobStatus.failed, error: 'x'),
        ]),
        assignments: assignmentsFor(),
      );
      await openAi(tester, bed);
      await tester.tap(find.text('Free form'));
      await tester.pumpAndSettle();
      await typeInto(tester, 'job-topic', 'trains');
      await tapKey(tester, 'generate-text');

      final table = tester.widget<DataTable>(key('jobs-table'));
      expect(table.rows, hasLength(3));
      expect((table.rows.first.key as ValueKey<String>).value, 'job-row-100');
      expect(
        find.descendant(of: key('job-status-100'), matching: find.text('Queued')),
        findsOneWidget,
      );
      // The content the job creates is named in the row.
      expect(key('job-content-100'), findsOneWidget);
    });

    testWidgets('assignment mode says when nothing waits, or why loading failed',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(
        assignments: FakeAssignmentsRepository(items: [
          assignmentRow('1', AssignmentStatus.ready),
        ]),
      );
      await openAi(tester, bed);

      // Empty code: refused before any request.
      await tapKey(tester, 'find-assignments');
      expect(find.text('Enter the participant code.'), findsOneWidget);
      expect(bed.assignments.listedCodes, isEmpty);

      await typeInto(tester, 'job-participant-code', 'P-009');
      await tapKey(tester, 'find-assignments');
      expect(key('no-waiting-assignments'), findsOneWidget);

      bed.assignments.listFailure =
          const ApiException('Participant not found.', statusCode: 404);
      await tapKey(tester, 'find-assignments');
      expect(textOf(tester, 'assignments-load-error'), 'Participant not found.');
    });

    testWidgets('changing the code drops the assignments listed for the old one',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(assignments: assignmentsFor());
      await openAi(tester, bed);
      await typeInto(tester, 'job-participant-code', 'P-001');
      await tapKey(tester, 'find-assignments');
      await tapKey(tester, 'job-assignment-2');
      await typeInto(tester, 'job-participant-code', 'P-002');
      expect(key('job-assignment-2'), findsNothing);
      await tapKey(tester, 'generate-text');
      expect(bed.ai.textRequests, isEmpty);
    });

    testWidgets('free form needs a topic and keeps the numbers in range',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed();
      await openAi(tester, bed);
      await tester.tap(find.text('Free form'));
      await tester.pumpAndSettle();

      // Defaults.
      expect(tester.widget<TextFormField>(key('job-points')).initialValue, '2');
      expect(tester.widget<TextFormField>(key('job-length')).initialValue, '90');

      await tapKey(tester, 'generate-text');
      expect(find.text('The topic is required.'), findsOneWidget);
      expect(bed.ai.textRequests, isEmpty);

      await typeInto(tester, 'job-topic', '   ');
      await tapKey(tester, 'generate-text');
      expect(find.text('The topic is required.'), findsOneWidget,
          reason: 'blanks are not a topic');

      await typeInto(tester, 'job-topic', 'trains');
      await typeInto(tester, 'job-points', '6');
      await typeInto(tester, 'job-length', '29');
      await tapKey(tester, 'generate-text');
      expect(find.text('The topic is required.'), findsNothing);
      expect(find.textContaining('whole number from 0 to 5'), findsOneWidget);
      expect(find.textContaining('from 30 to 600'), findsOneWidget);
      expect(bed.ai.textRequests, isEmpty);

      for (final bad in ['-1', '2.5', 'two', '']) {
        await typeInto(tester, 'job-points', bad);
        await tapKey(tester, 'generate-text');
        expect(find.textContaining('whole number from 0 to 5'), findsOneWidget,
            reason: 'points "$bad"');
      }
      await typeInto(tester, 'job-length', '601');
      await tapKey(tester, 'generate-text');
      expect(find.textContaining('from 30 to 600'), findsOneWidget);
      expect(bed.ai.textRequests, isEmpty);

      // The edges are accepted.
      await typeInto(tester, 'job-points', '0');
      await typeInto(tester, 'job-length', '30');
      await tapKey(tester, 'generate-text');
      await typeInto(tester, 'job-points', '5');
      await typeInto(tester, 'job-length', '600');
      await tapKey(tester, 'generate-text');
      expect(bed.ai.textRequests.map((r) => (r.interactionPoints, r.lengthSeconds)),
          [(0, 30), (5, 600)]);
    });

    testWidgets('a free-form request carries topic, name, interests and ids',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed();
      await openAi(tester, bed);
      await tester.tap(find.text('Free form'));
      await tester.pumpAndSettle();

      await typeInto(tester, 'job-topic', 'trains');
      await typeInto(tester, 'job-display-name', 'Sam');
      await typeInto(tester, 'job-interest-field', 'railways');
      await tapKey(tester, 'add-interest');
      await typeInto(tester, 'job-interest-field', 'maps');
      await tapKey(tester, 'add-interest');
      await typeInto(tester, 'job-interest-field', 'maps');
      await tapKey(tester, 'add-interest');
      expect(key('interest-railways'), findsOneWidget);
      expect(key('interest-maps'), findsOneWidget);
      // Deleting a chip removes it from the request.
      await typeInto(tester, 'job-interest-field', 'planes');
      await tapKey(tester, 'add-interest');
      await tester.tap(find.descendant(
          of: key('interest-planes'), matching: find.byType(Icon)));
      await tester.pumpAndSettle();
      expect(key('interest-planes'), findsNothing);

      await typeInto(tester, 'job-points', '3');
      await typeInto(tester, 'job-length', '120');
      await typeInto(tester, 'job-face', 'f1');
      await typeInto(tester, 'job-voice', 'v2');
      await tapKey(tester, 'generate-text');

      expect(bed.ai.textRequests.single.toJson(), {
        'topic': 'trains',
        'display_name': 'Sam',
        'interests': ['railways', 'maps'],
        'interaction_points': 3,
        'length_seconds': 120,
        'face_id': 'f1',
        'voice_id': 'v2',
      });
    });

    testWidgets('switching modes keeps what was typed', (tester) async {
      useWindow(tester, 1440, 2600);
      await openAi(tester, TestBed());
      await tester.tap(find.text('Free form'));
      await tester.pumpAndSettle();
      await typeInto(tester, 'job-topic', 'trains');
      await tester.tap(find.text('For an assignment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Free form'));
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: key('job-topic'),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(field).controller.text, 'trains');
    });

    for (final detail in [
      'budget_exceeded: estimate 3.20 exceeds the remaining 1.00 units',
      'provider_not_configured: no API key for the text provider',
    ]) {
      testWidgets('the server refusal is shown verbatim: ${detail.split(':').first}',
          (tester) async {
        useWindow(tester, 1440, 2600);
        final bed = TestBed()
          ..ai.textJobFailure = ApiException(detail, statusCode: 422);
        await openAi(tester, bed);
        await tester.tap(find.text('Free form'));
        await tester.pumpAndSettle();
        await typeInto(tester, 'job-topic', 'trains');
        await tapKey(tester, 'generate-text');

        expect(
          find.descendant(of: key('text-job-error'), matching: find.text(detail)),
          findsOneWidget,
        );
        expect(key('text-job-notice'), findsNothing);
        expect(key('jobs-table'), findsNothing, reason: 'no job was added');
        expect(key('no-jobs'), findsOneWidget);
      });
    }

    testWidgets('the free-text setting is explained in assignment mode',
        (tester) async {
      useWindow(tester, 1440, 2600);
      await openAi(tester, TestBed());
      expect(textOf(tester, 'free-text-note'), contains('is not sent'));

      final on = TestBed(
        ai: FakeAiRepository(
          status: const AiStatus(sendFreeText: true),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      await openAi(tester, on);
      expect(textOf(tester, 'free-text-note'), contains('sends'));
    });

    testWidgets('analysts do not get the form or the run button', (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(ai: FakeAiRepository(jobs: [
        aiJob('1', status: AiJobStatus.queued),
        aiJob('2', status: AiJobStatus.failed, error: 'boom'),
      ]));
      await openAi(tester, bed, role: 'analyst');
      expect(key('text-job-card'), findsNothing);
      expect(key('run-jobs'), findsNothing);
      expect(key('job-cancel-1'), findsNothing);
      expect(key('job-retry-2'), findsNothing);
      expect(key('job-open-1'), findsOneWidget, reason: 'reading the content is fine');
      expect(key('jobs-table'), findsOneWidget);
    });
  });

  group('jobs table', () {
    List<AiJob> oneOfEach() => [
          aiJob('5', status: AiJobStatus.cancelled),
          aiJob('4', status: AiJobStatus.failed, error: 'provider timeout after 30 s', attempts: 3),
          aiJob('3', status: AiJobStatus.succeeded, kind: AiJobKind.video, segmentId: 's2', actual: 0.3, estimate: 0.4),
          aiJob('2', status: AiJobStatus.running),
          aiJob('1', status: AiJobStatus.queued, contentId: null),
        ];

    testWidgets('shows a chip per status and the job fields', (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(ai: FakeAiRepository(jobs: oneOfEach()));
      await openAi(tester, bed);

      for (final (id, label) in [
        ('1', 'Queued'),
        ('2', 'Running'),
        ('3', 'Succeeded'),
        ('4', 'Failed'),
        ('5', 'Cancelled'),
      ]) {
        expect(
          find.descendant(of: key('job-status-$id'), matching: find.text(label)),
          findsOneWidget,
          reason: 'job $id',
        );
      }
      for (final h in [
        'Kind', 'Status', 'Provider', 'Content', 'Segment', 'Attempts',
        'Cost est. / actual', 'Created', 'Error'
      ]) {
        expect(find.text(h), findsWidgets, reason: h);
      }
      expect(textOf(tester, 'job-kind-3'), 'Video');
      expect(textOf(tester, 'job-kind-2'), 'Text');
      expect(textOf(tester, 'job-cost-3'), '0.40 / 0.30');
      expect(textOf(tester, 'job-cost-2'), '0.10 / -');
      expect(find.text('3 / 3'), findsOneWidget, reason: 'attempts of job 4');
      expect(find.text('s2'), findsOneWidget);
      expect(find.text('2026-09-29 10:00 UTC'), findsWidgets);
      expect(textOf(tester, 'job-content-2'), '#7');
    });

    testWidgets('the chip colours follow the status', (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(ai: FakeAiRepository(jobs: oneOfEach()));
      await openAi(tester, bed);

      BoxDecoration deco(String id) {
        final box = tester.widget<Container>(find.descendant(
          of: key('job-status-$id'),
          matching: find.byType(Container),
        ).first);
        return box.decoration! as BoxDecoration;
      }

      Color? fill(String id) => deco(id).color;
      expect(fill('1'), const Color(0xFFEAEDED), reason: 'queued is grey');
      expect(fill('2'), const Color(0xFFE4EEF9), reason: 'running is blue');
      expect(fill('3'), AppColors.successTint, reason: 'succeeded is green');
      expect(fill('4'), AppColors.errorTint, reason: 'failed is red');
      expect(fill('5'), isNull, reason: 'cancelled is outlined, not filled');
      expect(deco('5').border, isNotNull);
      expect(deco('4').border, isNull);
    });

    testWidgets('Cancel only for queued jobs, Retry only for failed ones',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(ai: FakeAiRepository(jobs: oneOfEach()));
      await openAi(tester, bed);

      for (final id in ['1', '2', '3', '4', '5']) {
        expect(key('job-cancel-$id'), id == '1' ? findsOneWidget : findsNothing,
            reason: 'cancel on job $id');
        expect(key('job-retry-$id'), id == '4' ? findsOneWidget : findsNothing,
            reason: 'retry on job $id');
      }
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // Open content needs a content id: job 1 has none.
      expect(key('job-open-1'), findsNothing);
      for (final id in ['2', '3', '4', '5']) {
        expect(key('job-open-$id'), findsOneWidget);
      }
    });

    testWidgets('Cancel and Retry act on the job and update its row',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(ai: FakeAiRepository(jobs: oneOfEach()));
      await openAi(tester, bed);

      await tapKey(tester, 'job-cancel-1');
      expect(bed.ai.cancelled, ['1']);
      expect(
        find.descendant(of: key('job-status-1'), matching: find.text('Cancelled')),
        findsOneWidget,
      );
      expect(key('job-cancel-1'), findsNothing);

      await tapKey(tester, 'job-retry-4');
      expect(bed.ai.retried, ['4']);
      expect(
        find.descendant(of: key('job-status-4'), matching: find.text('Queued')),
        findsOneWidget,
      );
      expect(key('job-retry-4'), findsNothing);
      expect(key('job-cancel-4'), findsOneWidget);
    });

    testWidgets('a refused action shows the server message', (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(ai: FakeAiRepository(jobs: oneOfEach()))
        ..ai.actionFailure =
            const ApiException('Only queued jobs can be cancelled.', statusCode: 409);
      await openAi(tester, bed);
      await tapKey(tester, 'job-cancel-1');
      expect(find.text('Only queued jobs can be cancelled.'), findsOneWidget);
    });

    testWidgets('the error has a tooltip and expands on tap', (tester) async {
      useWindow(tester, 1440, 2600);
      const long = 'provider timeout after 30 s while rendering segment s2; '
          'the provider answered 504 three times in a row';
      final bed = TestBed(
        ai: FakeAiRepository(jobs: [
          aiJob('4', status: AiJobStatus.failed, error: long),
        ]),
      );
      await openAi(tester, bed);

      expect(find.byTooltip(long), findsOneWidget);
      Text text() => tester.widget<Text>(key('job-error-text-4'));
      expect(text().maxLines, 2);
      await tapKey(tester, 'job-error-4');
      expect(text().maxLines, isNull, reason: 'expanded');
      await tapKey(tester, 'job-error-4');
      expect(text().maxLines, 2);
    });

    testWidgets('Run queued jobs now reports what happened and reloads',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(
        ai: FakeAiRepository(jobs: [
          aiJob('2', status: AiJobStatus.queued),
          aiJob('1', status: AiJobStatus.queued),
        ]),
      );
      await openAi(tester, bed);
      await tapKey(tester, 'run-jobs');

      expect(bed.ai.runs, [5]);
      expect(find.text('Processed 2 jobs: 1 succeeded, 1 failed.'), findsOneWidget);
      expect(
        find.descendant(of: key('job-status-1'), matching: find.text('Succeeded')),
        findsOneWidget,
      );
    });

    testWidgets('Refresh reads the status and the jobs again', (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed();
      await openAi(tester, bed);
      final reads = bed.ai.jobReads;
      bed.ai.jobList = [aiJob('9')];
      await tapKey(tester, 'refresh-jobs');
      expect(bed.ai.jobReads, reads + 1);
      expect(key('job-status-9'), findsOneWidget);
    });

    testWidgets('no jobs says so', (tester) async {
      useWindow(tester, 1440, 2600);
      await openAi(tester, TestBed());
      expect(key('no-jobs'), findsOneWidget);
      expect(find.text('No AI jobs yet.'), findsOneWidget);
    });

    testWidgets('Open content opens the content editor', (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(ai: FakeAiRepository(jobs: [
        aiJob('1', contentId: '2'),
      ]));
      await openAi(tester, bed);
      expect(find.text('Planes, draft'), findsOneWidget,
          reason: 'the title of the content is shown next to its id');
      await tapKey(tester, 'job-open-1');
      expect(key('content-status'), findsOneWidget);
      expect(find.text('Planes, draft'), findsWidgets);
      expect(key('mark-text-reviewed'), findsOneWidget);
    });
  });

  group('auto-refresh', () {
    testWidgets('no timer while nothing is queued or running', (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(ai: FakeAiRepository(jobs: [
        aiJob('1', status: AiJobStatus.succeeded),
        aiJob('2', status: AiJobStatus.failed, error: 'x'),
      ]));
      await openAi(tester, bed);
      expect(bed.timers, isEmpty);
      expect(key('auto-refresh-note'), findsNothing);
    });

    testWidgets('a queued job starts a 5 s timer that reads the jobs again',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(ai: FakeAiRepository(jobs: [
        aiJob('1', status: AiJobStatus.queued),
      ]));
      await openAi(tester, bed);

      expect(bed.timers, hasLength(1));
      expect(bed.timers.single.duration, const Duration(seconds: 5));
      expect(bed.timers.single.isActive, isTrue);
      expect(key('auto-refresh-note'), findsOneWidget);

      // The job is picked up: still running on the next read.
      final reads = bed.ai.jobReads;
      bed.ai.jobList = [aiJob('1', status: AiJobStatus.running)];
      bed.timers.last.fire();
      await tester.pumpAndSettle();
      expect(bed.ai.jobReads, reads + 1);
      expect(
        find.descendant(of: key('job-status-1'), matching: find.text('Running')),
        findsOneWidget,
      );
      expect(bed.timers, hasLength(2), reason: 'a running job keeps refreshing');
      expect(bed.timers.last.isActive, isTrue);

      // It finishes: the timer stops.
      bed.ai.jobList = [aiJob('1', status: AiJobStatus.succeeded)];
      bed.timers.last.fire();
      await tester.pumpAndSettle();
      expect(bed.timers, hasLength(2), reason: 'no third timer');
      expect(key('auto-refresh-note'), findsNothing);
      expect(
        find.descendant(of: key('job-status-1'), matching: find.text('Succeeded')),
        findsOneWidget,
      );
    });

    testWidgets('creating a job starts the timer when the table was idle',
        (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed();
      await openAi(tester, bed);
      expect(bed.timers, isEmpty);

      await tester.tap(find.text('Free form'));
      await tester.pumpAndSettle();
      await typeInto(tester, 'job-topic', 'trains');
      await tapKey(tester, 'generate-text');

      expect(bed.timers, hasLength(1));
      expect(bed.timers.single.duration, const Duration(seconds: 5));
      expect(key('auto-refresh-note'), findsOneWidget);

      // Cancelling the only queued job stops the refresh.
      await tapKey(tester, 'job-cancel-100');
      expect(bed.timers.single.cancelled, isTrue);
      expect(key('auto-refresh-note'), findsNothing);
    });

    testWidgets('leaving the study cancels the timer', (tester) async {
      useWindow(tester, 1440, 2600);
      final bed = TestBed(ai: FakeAiRepository(jobs: [
        aiJob('1', status: AiJobStatus.queued),
      ]));
      await openAi(tester, bed);
      final timer = bed.timers.single;
      expect(timer.isActive, isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(timer.cancelled, isTrue);
    });

    test('the controller schedules one timer at a time and stops when idle',
        () async {
      final repo = FakeAiRepository(jobs: [aiJob('1', status: AiJobStatus.queued)]);
      final timers = <ManualTimer>[];
      final c = AiController(
        repo,
        1,
        schedule: (d, f) {
          final t = ManualTimer(d, f);
          timers.add(t);
          return t;
        },
        pollInterval: const Duration(seconds: 2),
      );
      addTearDown(() {
        if (!c.isDisposed) c.dispose();
      });

      await c.load();
      expect(c.hasActiveJobs, isTrue);
      expect(c.autoRefreshing, isTrue);
      expect(timers, hasLength(1));
      expect(timers.single.duration, const Duration(seconds: 2));

      // Loading again while a timer is pending does not add another.
      await c.load();
      expect(timers, hasLength(1));

      repo.jobList = [aiJob('1', status: AiJobStatus.succeeded)];
      timers.single.fire();
      await Future<void>.delayed(Duration.zero);
      expect(c.autoRefreshing, isFalse);
      expect(c.hasActiveJobs, isFalse);
      expect(timers, hasLength(1));

      c.addJobs([aiJob('2', status: AiJobStatus.queued)]);
      expect(c.autoRefreshing, isTrue);
      expect(timers, hasLength(2));
      c.dispose();
      expect(timers.last.cancelled, isTrue);
    });

    test('a failed poll keeps the error and keeps polling while jobs are active',
        () async {
      final repo = FakeAiRepository(jobs: [aiJob('1', status: AiJobStatus.running)]);
      final timers = <ManualTimer>[];
      final c = AiController(repo, 1, schedule: (d, f) {
        final t = ManualTimer(d, f);
        timers.add(t);
        return t;
      });
      addTearDown(() {
        if (!c.isDisposed) c.dispose();
      });
      await c.load();
      repo.statusFailure = const ApiException('Could not reach the server.');
      timers.single.fire();
      await Future<void>.delayed(Duration.zero);
      expect(c.error, 'Could not reach the server.');
      expect(c.hasActiveJobs, isTrue, reason: 'the last known jobs stay');
      expect(timers, hasLength(2));
    });
  });

  group('layout', () {
    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('the AI tab fits ${width.toInt()} px in both modes',
          (tester) async {
        useWindow(tester, width, width == 360 ? 740 : 900);
        final bed = TestBed(
          ai: FakeAiRepository(status: configuredStatus, jobs: [
            aiJob('5', status: AiJobStatus.cancelled),
            aiJob('4',
                status: AiJobStatus.failed,
                error: 'provider timeout after 30 s while rendering segment s2',
                attempts: 3),
            aiJob('3', kind: AiJobKind.video, segmentId: 's2', actual: 0.3),
            aiJob('2', status: AiJobStatus.running),
            aiJob('1', status: AiJobStatus.queued),
          ]),
          assignments: assignmentsFor(),
        );
        await openAi(tester, bed, role: 'admin');
        expect(tester.takeException(), isNull, reason: 'assignment mode');

        await tapKey(tester, 'edit-cap');
        expect(tester.takeException(), isNull, reason: 'cap editor');

        await typeInto(tester, 'job-participant-code', 'P-001');
        await tapKey(tester, 'find-assignments');
        expect(key('job-assignment-2'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'assignments listed');

        await tapVisible(tester, find.text('Free form', skipOffstage: false));
        await typeInto(tester, 'job-interest-field', 'railways');
        await tapKey(tester, 'add-interest');
        await tapKey(tester, 'generate-text');
        expect(find.text('The topic is required.'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'free form with errors');

        await tester.ensureVisible(key('jobs-table'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'jobs table');
      });
    }

    testWidgets('a synthetic status with a refusal banner fits 360 px',
        (tester) async {
      useWindow(tester, 360, 740);
      final bed = TestBed()
        ..ai.textJobFailure = const ApiException(
          'budget_exceeded: estimate 3.20 exceeds the remaining 1.00 units of the study cost cap',
          statusCode: 422,
        );
      await openAi(tester, bed);
      await tapVisible(tester, find.text('Free form', skipOffstage: false));
      await typeInto(tester, 'job-topic', 'trains');
      await tapKey(tester, 'generate-text');
      expect(key('text-job-error'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
