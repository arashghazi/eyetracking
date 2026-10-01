import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_admin/features/ai/presentation/ai_widgets.dart';
import 'package:research_admin/features/live/domain/live_models.dart';
import 'package:research_admin/features/pilot/presentation/pilot_widgets.dart';

import 'fakes.dart';
import 'helpers.dart';
import 'live_fixtures.dart';
import 'pilot_fixtures.dart';

Finder key(String k) => find.byKey(Key(k), skipOffstage: false);

Future<void> tapKey(WidgetTester tester, String k) => tapVisible(tester, key(k));

/// The text of a `Text.rich` figure.
String plain(WidgetTester tester, String k) =>
    tester.widget<Text>(key(k)).textSpan!.toPlainText();

String textOf(WidgetTester tester, String k) {
  final w = tester.widget<Text>(key(k));
  return w.data ?? w.textSpan!.toPlainText();
}

/// The value of a `FactRow`: the second Text in it (after the label).
String factRowValue(WidgetTester tester, String k) {
  final texts = tester
      .widgetList<Text>(find.descendant(of: key(k), matching: find.byType(Text, skipOffstage: false)))
      .toList();
  return texts[1].data ?? texts[1].textSpan!.toPlainText();
}

/// The value of a fact of the session conversation section.
String fact(WidgetTester tester, String k) => tester
    .widget<SelectableText>(find.descendant(
      of: key(k),
      matching: find.byType(SelectableText, skipOffstage: false),
    ))
    .data!;

Finder inside(String k, String text) => find.descendant(
      of: key(k),
      matching: find.text(text, skipOffstage: false),
    );

// ------------------------------------------------------------------ AI tab

Future<void> openAi(
  WidgetTester tester,
  TestBed bed, {
  String role = 'researcher',
  double width = 1440,
}) async {
  useWindow(tester, width, width < 500 ? 3200 : 2600);
  await openStudy(tester, bed, role: role);
  await openTab(tester, 'AI');
}

TestBed liveAiBed({LiveAvatarStatus? status}) {
  final bed = TestBed();
  bed.live.statusResult = status ?? sampleLiveStatus();
  return bed;
}

// --------------------------------------------------------- session detail

Future<void> openConversation(
  WidgetTester tester,
  TestBed bed, {
  String role = 'researcher',
  double width = 1440,
}) async {
  useWindow(tester, width, width < 500 ? 4200 : 3200);
  await openStudy(tester, bed, role: role);
  await openTab(tester, 'Sessions');
  await tester.tap(find.text('P-001'));
  await tester.pumpAndSettle();
}

TestBed conversationBed({
  bool withText = false,
  bool open = false,
  int distress = 0,
}) {
  final bed = TestBed();
  bed.live.conversations['21'] =
      sampleConversation(withText: withText, open: open, distress: distress);
  return bed;
}

// ------------------------------------------------------------------ pilot

Future<void> openPilot(
  WidgetTester tester,
  TestBed bed, {
  String role = 'researcher',
  double width = 1440,
  double height = 3000,
}) async {
  useWindow(tester, width, height);
  await openStudy(tester, bed, role: role);
  await openTab(tester, 'Pilot');
}

TestBed monitorBed({List<ConversationMonitor?>? conversations, List<LiveStatus>? queue}) {
  final bed = TestBed();
  bed.pilot
    ..active = activeSessions
    ..liveQueue = queue ?? [liveStatus()]
    ..liveConversationQueue = conversations ?? [sampleMonitor()];
  return bed;
}

List<ManualTimer> armed(TestBed bed) => [for (final t in bed.timers) if (t.isActive) t];

List<String> cellStrings(Widget w) {
  if (w is Text) return [w.data ?? w.textSpan?.toPlainText() ?? ''];
  if (w is CodeText) return [w.code];
  if (w is SingleChildRenderObjectWidget && w.child != null) return cellStrings(w.child!);
  if (w is MultiChildRenderObjectWidget) return [for (final c in w.children) ...cellStrings(c)];
  if (w is ProxyWidget) return cellStrings(w.child);
  return const [];
}

/// The cells of the report row of [sessionId], by column label.
Map<String, String> reportRowByColumn(WidgetTester tester, String sessionId) {
  final table = tester.widget<DataTable>(key('report-rows'));
  final labels = [for (final c in table.columns) (c.label as Text).data!];
  final row = table.rows.firstWhere((r) => r.key == ValueKey('report-row-$sessionId'));
  return {
    for (var i = 0; i < labels.length; i++) labels[i]: cellStrings(row.cells[i].child).join(' '),
  };
}

Future<TestBed> openReport(
  WidgetTester tester, {
  String role = 'researcher',
  double width = 1440,
  Map<String, ConversationReportColumns>? conversation,
}) async {
  final bed = TestBed();
  bed.pilot
    ..reportResult = sampleReport()
    ..reportConversation = conversation ??
        {
          '21': const ConversationReportColumns(
            turns: 4,
            onTopicShare: 0.75,
            distress: 1,
            endReason: 'turn_limit',
          ),
        };
  await openPilot(tester, bed, role: role, width: width, height: width < 500 ? 2400 : 5200);
  await tapVisible(tester, key('pilot-section-report'));
  return bed;
}

void main() {
  group('AI tab: Live avatar card', () {
    testWidgets('is absent for a service without the live endpoints (404)',
        (tester) async {
      await openAi(tester, TestBed());
      expect(key('ai-status-card'), findsOneWidget);
      expect(key('live-avatar-card'), findsNothing);
    });

    testWidgets('shows the providers, estimates, shared budget, open conversations and the note',
        (tester) async {
      final bed = liveAiBed();
      await openAi(tester, bed);

      expect(bed.live.statusReads, 1);
      expect(find.text('Live avatar'), findsOneWidget);
      for (final p in ['live-reply', 'live-speech', 'live-avatar']) {
        expect(textOf(tester, '$p-name'), 'fake', reason: p);
        expect(inside('$p-state', 'Configured'), findsOneWidget, reason: p);
        expect(inside('$p-synthetic', SyntheticBadge.text), findsOneWidget, reason: p);
      }
      expect(inside('live-avatar-streaming', 'No streaming avatar connected'), findsOneWidget);
      expect(plain(tester, 'live-per-turn'), 'Per reply 0.012 units');
      expect(plain(tester, 'live-per-minute'), 'Avatar per minute 0.00 units');
      expect(plain(tester, 'live-budget-cap'), 'Cap 5.00');
      expect(plain(tester, 'live-budget-spent'), 'Spent 1.25');
      expect(plain(tester, 'live-budget-remaining'), 'Remaining 3.75');
      expect(plain(tester, 'live-open-conversations'), 'Open conversations 2');
      expect(textOf(tester, 'live-status-note'), startsWith('Development providers are synthetic'));
      expect(find.text('Reply provider'), findsOneWidget);
      expect(find.text('Speech provider'), findsOneWidget);
      expect(find.text('Avatar provider'), findsOneWidget);
    });

    testWidgets('names the model and effort, and a streaming avatar', (tester) async {
      await openAi(tester, liveAiBed(status: claudeLiveStatus()));

      expect(textOf(tester, 'live-reply-name'), 'anthropic, claude-opus-5-5, effort low');
      expect(inside('live-reply-state', 'Configured'), findsOneWidget);
      expect(key('live-reply-synthetic'), findsNothing);
      expect(textOf(tester, 'live-speech-name'), 'whisper_http, base, http://127.0.0.1:8200');
      expect(key('live-speech-synthetic'), findsNothing);
      expect(textOf(tester, 'live-avatar-name'), 'streaming-vendor');
      expect(inside('live-avatar-streaming', 'Streaming avatar'), findsOneWidget);
      expect(find.text('No streaming avatar connected'), findsNothing);
    });

    testWidgets('a provider without a key says Not configured', (tester) async {
      await openAi(tester, liveAiBed(status: claudeLiveStatus(replyConfigured: false)));
      expect(inside('live-reply-state', 'Not configured'), findsOneWidget);
      expect(inside('live-speech-state', 'Configured'), findsOneWidget);
    });

    testWidgets("a refusal is shown as the server wrote it, and Try again reads it again",
        (tester) async {
      final bed = liveAiBed()
        ..live.statusFailure = const ApiException(
          'You are not a member of this study.',
          statusCode: 403,
        );
      await openAi(tester, bed);

      expect(tester.widget<MessageBanner>(key('live-status-error')).message,
          'You are not a member of this study.');
      expect(key('live-reply-name'), findsNothing);

      bed.live.statusFailure = null;
      await tapKey(tester, 'live-status-retry');
      expect(key('live-status-error'), findsNothing);
      expect(textOf(tester, 'live-reply-name'), 'fake');
      expect(bed.live.statusReads, 2);
    });

    testWidgets('Refresh reads the status again', (tester) async {
      final bed = liveAiBed();
      await openAi(tester, bed);
      expect(bed.live.statusReads, 1);

      bed.live.statusResult = LiveAvatarStatus.fromJson(liveStatusJson(open: 5));
      await tapKey(tester, 'refresh-jobs');
      expect(bed.live.statusReads, 2);
      expect(plain(tester, 'live-open-conversations'), 'Open conversations 5');
    });

    testWidgets('a new cost cap makes the card read the shared budget again',
        (tester) async {
      final bed = liveAiBed();
      await openAi(tester, bed, role: 'admin');
      expect(bed.live.statusReads, 1);

      await tapKey(tester, 'edit-cap');
      await tester.ensureVisible(key('cap-field'));
      await tester.enterText(key('cap-field'), '9');
      await tapKey(tester, 'save-cap');
      expect(bed.ai.budgetChanges, [9.0]);
      expect(bed.live.statusReads, 2);
    });

    testWidgets('analysts see the same card', (tester) async {
      await openAi(tester, liveAiBed(), role: 'analyst');
      expect(key('live-avatar-card'), findsOneWidget);
      expect(textOf(tester, 'live-reply-name'), 'fake');
      expect(key('edit-cap'), findsNothing);
    });

    for (final width in [360.0, 800.0, 1440.0]) {
      for (final (name, status) in [
        ('development providers (the longest badges)', sampleLiveStatus()),
        ('Claude, Whisper and a streaming avatar', claudeLiveStatus()),
      ]) {
        testWidgets('fits ${width.toInt()} px with $name', (tester) async {
          await openAi(tester, liveAiBed(status: status), width: width);
          expect(tester.takeException(), isNull);
          expect(key('live-avatar-card'), findsOneWidget);
          expect(key('live-open-conversations'), findsOneWidget);
        });
      }
    }
  });

  group('AI tab: text jobs and live assignments', () {
    testWidgets('a live assignment waiting for its topic has nothing to generate',
        (tester) async {
      final bed = TestBed(
        assignments: FakeAssignmentsRepository(items: [
          assignmentRow('3', AssignmentStatus.pendingTopic),
          assignmentRow('9', AssignmentStatus.pendingTopic,
              protocol: 'Trains live', path: ProtocolPath.liveConversation),
        ]),
      );
      await openAi(tester, bed);
      await tester.ensureVisible(key('job-participant-code'));
      await tester.enterText(key('job-participant-code'), 'P-001');
      await tapKey(tester, 'find-assignments');

      expect(key('job-assignment-3'), findsOneWidget, reason: 'an interest conversation does');
      expect(key('job-assignment-9'), findsNothing);
    });
  });

  group('Session detail: Conversation', () {
    testWidgets('a session without a conversation shows nothing (404)', (tester) async {
      final bed = TestBed();
      await openConversation(tester, bed);

      expect(find.text('Session of P-001'), findsOneWidget);
      expect(bed.live.conversationReads, ['21'], reason: 'it was asked');
      expect(key('section-conversation'), findsNothing);
      expect(find.text('Conversation'), findsNothing);
      expect(key('conversation-error'), findsNothing);
      // The rest of the page is there.
      expect(key('card-face'), findsOneWidget);
    });

    testWidgets('shows topic, mode, transcript, status, end reason, turns and cost',
        (tester) async {
      await openConversation(tester, conversationBed());

      expect(key('section-conversation'), findsOneWidget);
      expect(find.text('Conversation'), findsOneWidget);
      expect(fact(tester, 'conv-topic'), 'trains');
      expect(fact(tester, 'conv-mode'), 'Speech');
      expect(fact(tester, 'conv-transcript'), 'No');
      expect(fact(tester, 'conv-status'), 'Closed');
      expect(fact(tester, 'conv-end'), 'Participant pressed End');
      expect(fact(tester, 'conv-turns'), '3');
      expect(fact(tester, 'conv-cost'), '0.0361 units');
    });

    testWidgets('an open conversation has no end reason yet', (tester) async {
      await openConversation(tester, conversationBed(open: true));
      expect(fact(tester, 'conv-status'), 'Open');
      expect(fact(tester, 'conv-end'), '-');
    });

    testWidgets('the outcome with the note that the reply model judges it',
        (tester) async {
      await openConversation(tester, conversationBed());

      expect(fact(tester, 'outcome-participant-turns'), '2');
      expect(fact(tester, 'outcome-on-topic'), '50 %');
      expect(fact(tester, 'outcome-redirects'), '1');
      expect(fact(tester, 'outcome-distress'), '0');
      expect(textOf(tester, 'conversation-outcome-note'), contains('reply model'));
      expect(textOf(tester, 'conversation-outcome-note'), contains('not understanding'));
    });

    testWidgets('an unjudged conversation shows a dash for the on-topic share',
        (tester) async {
      final json = conversationJson();
      (json['outcome'] as Map<String, dynamic>)
        ..['on_topic_share'] = null
        ..['note'] = null;
      final bed = TestBed();
      bed.live.conversations['21'] = StaffConversation.fromJson(json);
      await openConversation(tester, bed);
      expect(fact(tester, 'outcome-on-topic'), '—');
      // Without a note from the server the section still says who judges.
      expect(textOf(tester, 'conversation-outcome-note'), contains('reply model'));
    });

    testWidgets('without a kept transcript every turn says Text not kept',
        (tester) async {
      await openConversation(tester, conversationBed());

      expect(key('conversation-turns'), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        expect(key('turn-$i'), findsOneWidget, reason: 'turn $i');
        expect(inside('turn-$i', 'Text not kept'), findsOneWidget, reason: 'turn $i');
      }
      expect(find.textContaining('steam trains'), findsNothing);
      expect(find.text('Text not kept'), findsNWidgets(5));
    });

    testWidgets('with a kept transcript the text is shown', (tester) async {
      await openConversation(tester, conversationBed(withText: true));

      expect(fact(tester, 'conv-transcript'), 'Yes');
      expect(find.text('Text not kept'), findsNothing);
      expect(inside('turn-0', 'Hi Sam! Tell me about trains.'), findsOneWidget);
      expect(inside('turn-1', 'I like steam trains'), findsOneWidget);
      expect(inside('turn-4', 'Thank you for telling me. Would you like a break?'), findsOneWidget);
    });

    testWidgets('each turn shows its role, session time and flags as chips', (tester) async {
      await openConversation(tester, conversationBed());

      expect(inside('turn-0', 'Avatar'), findsOneWidget);
      expect(inside('turn-0', '00:01.000'), findsOneWidget);
      expect(inside('turn-0', 'Scripted line'), findsOneWidget);
      expect(inside('turn-0', 'Opening'), findsOneWidget);
      expect(inside('turn-1', 'Participant'), findsOneWidget);
      expect(inside('turn-1', 'Speech'), findsOneWidget);
      expect(inside('turn-1', 'On topic'), findsOneWidget);
      expect(inside('turn-3', 'Off topic'), findsOneWidget);
      expect(inside('turn-4', 'Redirect line'), findsOneWidget);
      // A turn without flags has no chips and still shows.
      expect(find.descendant(of: key('turn-2'), matching: find.byType(StateChip, skipOffstage: false)),
          findsNothing);
    });

    testWidgets('distress is highlighted in the turn and in the outcome', (tester) async {
      await openConversation(tester, conversationBed(distress: 1));

      expect(fact(tester, 'outcome-distress'), '1');
      final value = tester.widget<SelectableText>(find.descendant(
        of: key('outcome-distress'),
        matching: find.byType(SelectableText, skipOffstage: false),
      ));
      expect(value.style!.color, AppColors.error);
      final chip = tester
          .widgetList<StateChip>(find.descendant(
            of: key('turn-3'),
            matching: find.byType(StateChip, skipOffstage: false),
          ))
          .firstWhere((c) => c.label == 'Distress');
      expect(chip.foreground, AppColors.error);
      expect(chip.background, AppColors.errorTint);
    });

    testWidgets('says that opening it is logged, and shows the server note',
        (tester) async {
      await openConversation(tester, conversationBed());
      expect(find.textContaining('written to the access log'), findsOneWidget);
      expect(find.textContaining('(live_transcript)'), findsOneWidget);
      expect(find.textContaining('Audio is never kept'), findsOneWidget);
    });

    testWidgets('a conversation without turns says so', (tester) async {
      final json = conversationJson()..['turns'] = <Object>[];
      final bed = TestBed();
      bed.live.conversations['21'] = StaffConversation.fromJson(json);
      await openConversation(tester, bed);
      expect(key('conversation-no-turns'), findsOneWidget);
    });

    testWidgets('a refusal other than 404 is shown as written, with Try again',
        (tester) async {
      final bed = conversationBed()
        ..live.conversationFailure = const ApiException(
          'You are not a member of this study.',
          statusCode: 403,
        );
      await openConversation(tester, bed);

      expect(tester.widget<MessageBanner>(key('conversation-error')).message,
          'You are not a member of this study.');
      expect(key('turn-0'), findsNothing);

      bed.live.conversationFailure = null;
      await tapKey(tester, 'conversation-retry');
      expect(key('conversation-error'), findsNothing);
      expect(key('turn-0'), findsOneWidget);
    });

    testWidgets('analysts read it too', (tester) async {
      await openConversation(tester, conversationBed(withText: true), role: 'analyst');
      expect(key('section-conversation'), findsOneWidget);
      expect(inside('turn-1', 'I like steam trains'), findsOneWidget);
    });

    testWidgets('a session of the live path: protocol, conversation and the third criterion',
        (tester) async {
      final detail = <String, dynamic>{
        ...interestSessionDetailJson,
        'protocol': {
          'id': 6,
          'name': 'Trains live',
          'version': 1,
          'path': 'live_conversation',
        },
      };
      final bed = TestBed(sessions: FakeSessionsRepository(detailJson: detail));
      bed.live.conversations['21'] = sampleConversation(withText: true);
      await openConversation(tester, bed);

      expect(inside('section-protocol', ProtocolPath.liveConversation.label), findsOneWidget);
      expect(find.text('Conversation held (judged by the reply model)'), findsOneWidget);
      expect(find.text('Comprehension or number task kept'), findsNothing);
      expect(key('section-conversation'), findsOneWidget);
      // The conversation comes right after the protocol, before the device.
      final conversationTop = tester.getTopLeft(find.byKey(const Key('section-conversation'))).dy;
      final protocolTop = tester.getTopLeft(find.byKey(const Key('section-protocol'))).dy;
      expect(conversationTop, greaterThan(protocolTop));
    });

    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('fits ${width.toInt()} px, with long text', (tester) async {
        final json = conversationJson(withText: true, distress: 2);
        (json['turns'] as List<dynamic>)[1]['text'] =
            'I really like steam trains because ' * 12;
        (json['conversation'] as Map<String, dynamic>)['topic'] =
            'a very long topic about old railways in the mountains';
        final bed = TestBed();
        bed.live.conversations['21'] = StaffConversation.fromJson(json);
        await openConversation(tester, bed, width: width);
        expect(tester.takeException(), isNull);
        expect(key('section-conversation'), findsOneWidget);
        expect(key('turn-4'), findsOneWidget);
      });
    }
  });

  group('Pilot: Live monitor, conversation block', () {
    testWidgets('shows status, mode, turns, distress, redirects and the last turn',
        (tester) async {
      final bed = monitorBed();
      await openPilot(tester, bed);
      await tapKey(tester, 'monitor-21');

      expect(key('live-conversation'), findsOneWidget);
      expect(find.text('Conversation'), findsOneWidget);
      expect(factRowValue(tester, 'live-conv-status'), 'Open');
      expect(factRowValue(tester, 'live-conv-mode'), 'Speech');
      expect(factRowValue(tester, 'live-conv-turns'), '3');
      expect(factRowValue(tester, 'live-conv-distress'), '0');
      expect(factRowValue(tester, 'live-conv-redirects'), '1');
      expect(inside('live-conv-last', 'Avatar'), findsOneWidget);
      expect(inside('live-conv-last', '01:23.500'), findsOneWidget);
      expect(inside('live-conv-last', 'Scripted line'), findsOneWidget);
      expect(inside('live-conv-last', 'Redirect line'), findsOneWidget);
      expect(key('live-conv-end'), findsNothing, reason: 'still open');
    });

    testWidgets('distress above zero is highlighted', (tester) async {
      await openPilot(tester, monitorBed(conversations: [sampleMonitor(distress: 2)]));
      await tapKey(tester, 'monitor-21');

      final box = tester.widget<Container>(key('live-conv-distress'));
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.color, AppColors.errorTint);
      expect(find.descendant(of: key('live-conv-distress'), matching: find.text('Distress', skipOffstage: false)),
          findsOneWidget);
      expect(find.descendant(of: key('live-conv-distress'), matching: find.text('2', skipOffstage: false)),
          findsOneWidget);
    });

    testWidgets('zero distress is plain', (tester) async {
      await openPilot(tester, monitorBed());
      await tapKey(tester, 'monitor-21');
      expect(find.descendant(of: key('live-conv-distress'), matching: find.byType(Icon, skipOffstage: false)),
          findsNothing);
      expect(tester.widget<FactRow>(key('live-conv-distress')).value, '0');
    });

    testWidgets('a closed conversation shows its end reason', (tester) async {
      await openPilot(
        tester,
        monitorBed(conversations: [
          sampleMonitor(status: 'closed', endReason: 'turn_limit'),
        ]),
      );
      await tapKey(tester, 'monitor-21');
      expect(factRowValue(tester, 'live-conv-status'), 'Closed');
      expect(factRowValue(tester, 'live-conv-end'), 'Turn limit reached');
    });

    testWidgets('no last turn yet', (tester) async {
      await openPilot(
        tester,
        monitorBed(conversations: [sampleMonitor(lastTurn: false)]),
      );
      await tapKey(tester, 'monitor-21');
      expect(inside('live-conv-last', 'No turn yet'), findsOneWidget);
    });

    testWidgets('a session without a conversation has no block', (tester) async {
      final bed = monitorBed(conversations: []);
      await openPilot(tester, bed);
      await tapKey(tester, 'monitor-21');
      expect(key('live-panel'), findsOneWidget);
      expect(key('live-conversation'), findsNothing);
      expect(find.text('Conversation'), findsNothing);
    });

    testWidgets('the block follows the polling', (tester) async {
      final bed = monitorBed(
        queue: [liveStatus(), liveStatus()],
        conversations: [sampleMonitor(), sampleMonitor(distress: 1)],
      );
      await openPilot(tester, bed);
      await tapKey(tester, 'monitor-21');
      expect(factRowValue(tester, 'live-conv-distress'), '0');

      armed(bed).single.fire();
      await tester.pumpAndSettle();
      final decoration = tester.widget<Container>(key('live-conv-distress')).decoration! as BoxDecoration;
      expect(decoration.color, AppColors.errorTint);
    });

    testWidgets('closing the panel removes the block', (tester) async {
      await openPilot(tester, monitorBed());
      await tapKey(tester, 'monitor-21');
      expect(key('live-conversation'), findsOneWidget);
      await tapKey(tester, 'live-close');
      expect(key('live-conversation'), findsNothing);
    });

    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('fits ${width.toInt()} px', (tester) async {
        final bed = monitorBed(conversations: [sampleMonitor(distress: 3)]);
        await openPilot(tester, bed, width: width, height: width < 500 ? 4000 : 3000);
        await tapKey(tester, 'monitor-21');
        expect(tester.takeException(), isNull);
        expect(key('live-conversation'), findsOneWidget);
      });
    }
  });

  group('Pilot: Report, conversation columns', () {
    testWidgets('the rows table has the four conversation columns', (tester) async {
      await openReport(tester);
      final table = tester.widget<DataTable>(key('report-rows'));
      final labels = [for (final c in table.columns) (c.label as Text).data!];
      expect(labels, containsAllInOrder([
        'Number task',
        'Conversation turns',
        'On-topic share',
        'Conversation distress',
        'Conversation end',
        'Debrief',
      ]));
      expect(table.columns.every((c) => c.label is Text), isTrue);
      expect(table.rows.every((r) => r.cells.length == table.columns.length), isTrue);
    });

    testWidgets('a row with a conversation shows its numbers', (tester) async {
      await openReport(tester);
      final row = reportRowByColumn(tester, '21');
      expect(row['Conversation turns'], '4');
      expect(row['On-topic share'], '75 %');
      expect(row['Conversation distress'], '1');
      expect(row['Conversation end'], 'Turn limit reached');
      // The other columns are unchanged.
      expect(row['Participant'], 'P-001');
      expect(row['Debrief'], 'answered');
    });

    testWidgets('a row without a conversation shows dashes', (tester) async {
      await openReport(tester);
      final row = reportRowByColumn(tester, '22');
      expect(row['Conversation turns'], '-');
      expect(row['On-topic share'], '—');
      expect(row['Conversation distress'], '-');
      expect(row['Conversation end'], '-');
    });

    testWidgets('a conversation that was never judged shows a dash for the share',
        (tester) async {
      await openReport(tester, conversation: {
        '21': const ConversationReportColumns(turns: 1, onTopicShare: null, distress: 0),
      });
      final row = reportRowByColumn(tester, '21');
      expect(row['Conversation turns'], '1');
      expect(row['On-topic share'], '—');
      expect(row['Conversation distress'], '0');
      expect(row['Conversation end'], '-');
    });

    testWidgets('analysts read the columns too', (tester) async {
      await openReport(tester, role: 'analyst');
      expect(reportRowByColumn(tester, '21')['Conversation turns'], '4');
    });

    testWidgets('Include synthetic reads the rows again and keeps the columns',
        (tester) async {
      final bed = await openReport(tester);
      bed.pilot.reportConversation = {
        '21': const ConversationReportColumns(turns: 6, onTopicShare: 1, distress: 0),
        '22': const ConversationReportColumns(turns: 2, onTopicShare: 0.5, distress: 0),
      };
      await tapKey(tester, 'report-include-synthetic');
      expect(bed.pilot.reportRequests, [false, true]);
      expect(reportRowByColumn(tester, '21')['Conversation turns'], '6');
      expect(reportRowByColumn(tester, '22')['On-topic share'], '50 %');
    });

    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('the table scrolls sideways and fits ${width.toInt()} px',
          (tester) async {
        await openReport(tester, width: width);
        expect(tester.takeException(), isNull);
        final scroll = tester.widget<SingleChildScrollView>(
          find.ancestor(of: key('report-rows'), matching: find.byType(SingleChildScrollView)).first,
        );
        expect(scroll.scrollDirection, Axis.horizontal);
      });
    }
  });
}
