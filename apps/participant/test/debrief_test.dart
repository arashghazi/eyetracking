import 'dart:async';
import 'dart:convert';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:participant_app/app_scope.dart';
import 'package:participant_app/features/debrief/data/api_debrief_repository.dart';
import 'package:participant_app/features/debrief/domain/debrief_models.dart';
import 'package:participant_app/features/debrief/presentation/debrief_card.dart';
import 'package:participant_app/features/session/presentation/session_flow_screen.dart';

import 'debrief_kit.dart';
import 'fakes.dart';
import 'helpers.dart';
import 'session_kit.dart';

const thanks = 'Thank you. Your answers help us improve the sessions.';
const changedMessage = 'the questions have changed; please reload them';

/// Pumps the card the way the summary page holds it.
Future<void> pumpCard(
  WidgetTester tester,
  FakeDebriefRepository repo, {
  double width = 800,
  double height = 1400,
  String sessionId = '11',
}) async {
  useWindow(tester, width, height);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: PageFrame(
          maxWidth: 960,
          buildAll: true,
          children: [DebriefCard(repository: repo, sessionId: sessionId)],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The widget with [key], also when it is built but scrolled out of view.
Finder byKey(String key) => find.byKey(Key(key), skipOffstage: false);

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = byKey(key);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> type(WidgetTester tester, String key, String text) async {
  final finder = byKey(key);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.enterText(finder, text);
  await tester.pump();
}

bool chipSelected(WidgetTester tester, String key) =>
    tester.widget<ChoiceChip>(byKey(key)).selected;

bool sendEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(byKey('debrief-send')).onPressed != null;

Future<void> answerRequired(WidgetTester tester) async {
  await tapKey(tester, 'debrief-clear-4');
  await tapKey(tester, 'debrief-comfort-2');
  await tapKey(tester, 'debrief-uncomfortable-no');
}

const _card = 'debrief-card';

void main() {
  group('visibility', () {
    testWidgets('shown when the study asks and nothing was answered', (
      tester,
    ) async {
      final repo = FakeDebriefRepository(state: askingDebrief);
      await pumpCard(tester, repo);
      expect(byKey(_card), findsOneWidget);
      expect(find.text('A few questions about this session'), findsOneWidget);
      expect(find.text('Send answers'), findsOneWidget);
      expect(find.text('Skip these questions'), findsOneWidget);
      expect(repo.loads, ['11']);
    });

    testWidgets('hidden when the debrief is switched off', (tester) async {
      final repo = FakeDebriefRepository(state: disabledDebrief);
      await pumpCard(tester, repo);
      expect(byKey(_card), findsNothing);
      expect(find.text('A few questions about this session'), findsNothing);
    });

    testWidgets('hidden when the response is enabled but has no form', (
      tester,
    ) async {
      final repo = FakeDebriefRepository(
        state: const SessionDebrief(enabled: true, sessionEnded: true),
      );
      await pumpCard(tester, repo);
      expect(byKey(_card), findsNothing);
    });

    testWidgets('hidden when the participant already answered', (tester) async {
      final repo = FakeDebriefRepository(
        state: const SessionDebrief(
          enabled: true,
          sessionEnded: true,
          form: debriefForm3,
          answer: DebriefAnswer(formVersion: 3, answers: {'clear': 4}),
        ),
      );
      await pumpCard(tester, repo);
      expect(byKey(_card), findsNothing);
      expect(byKey('debrief-thanks'), findsNothing);
    });

    testWidgets('hidden when the participant skipped earlier', (tester) async {
      final repo = FakeDebriefRepository(
        state: const SessionDebrief(
          enabled: true,
          sessionEnded: true,
          form: debriefForm3,
          answer: DebriefAnswer(formVersion: 3, skipped: true),
        ),
      );
      await pumpCard(tester, repo);
      expect(byKey(_card), findsNothing);
    });

    testWidgets('hidden until the session has ended', (tester) async {
      final repo = FakeDebriefRepository(
        state: const SessionDebrief(
          enabled: true,
          sessionEnded: false,
          form: debriefForm3,
        ),
      );
      await pumpCard(tester, repo);
      expect(byKey(_card), findsNothing);
    });

    testWidgets('a failed load hides the card without an error', (
      tester,
    ) async {
      final repo = FakeDebriefRepository(state: askingDebrief)
        ..loadFailure = const ApiException('Not found.', statusCode: 404);
      await pumpCard(tester, repo);
      expect(byKey(_card), findsNothing);
      expect(find.text('Not found.'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('required questions', () {
    testWidgets('only required questions are marked', (tester) async {
      await pumpCard(tester, FakeDebriefRepository(state: askingDebrief));
      for (final key in ['clear', 'comfort', 'uncomfortable']) {
        expect(byKey('debrief-$key-required'), findsOneWidget, reason: key);
      }
      for (final key in ['what', 'setup', 'change']) {
        expect(byKey('debrief-$key-required'), findsNothing, reason: key);
      }
      expect(find.text('Required'), findsNWidgets(3));
    });

    testWidgets(
      'Send is enabled only when every required question has an answer',
      (tester) async {
        await pumpCard(tester, FakeDebriefRepository(state: askingDebrief));
        expect(sendEnabled(tester), isFalse);

        await tapKey(tester, 'debrief-clear-4');
        expect(sendEnabled(tester), isFalse);
        await tapKey(tester, 'debrief-comfort-2');
        expect(sendEnabled(tester), isFalse);
        await tapKey(tester, 'debrief-uncomfortable-yes');
        expect(sendEnabled(tester), isTrue);

        // Optional questions never matter.
        expect(chipSelected(tester, 'debrief-setup-option-0'), isFalse);
        expect(sendEnabled(tester), isTrue);

        // Taking an answer back makes it unanswered again.
        await tapKey(tester, 'debrief-comfort-2');
        expect(chipSelected(tester, 'debrief-comfort-2'), isFalse);
        expect(sendEnabled(tester), isFalse);
      },
    );

    testWidgets('"No" is an answer to a required yes/no question', (
      tester,
    ) async {
      await pumpCard(tester, FakeDebriefRepository(state: askingDebrief));
      await answerRequired(tester);
      expect(chipSelected(tester, 'debrief-uncomfortable-no'), isTrue);
      expect(sendEnabled(tester), isTrue);
    });

    testWidgets('a required text question needs more than spaces', (
      tester,
    ) async {
      final repo = FakeDebriefRepository(
        state: const SessionDebrief(
          enabled: true,
          sessionEnded: true,
          form: ParticipantDebriefForm(
            version: 1,
            questions: [
              ParticipantDebriefQuestion(
                key: 'why',
                type: ParticipantDebriefQuestionType.text,
                prompt: 'Why?',
                required: true,
              ),
            ],
          ),
        ),
      );
      await pumpCard(tester, repo);
      expect(sendEnabled(tester), isFalse);
      await type(tester, 'debrief-why-text', '    ');
      expect(sendEnabled(tester), isFalse);
      await type(tester, 'debrief-why-text', ' because ');
      expect(sendEnabled(tester), isTrue);
      await tester.tap(byKey('debrief-send'));
      await tester.pumpAndSettle();
      expect(repo.lastBody['answers'], {'why': 'because'});
    });

    testWidgets('Skip is available while required questions are open', (
      tester,
    ) async {
      await pumpCard(tester, FakeDebriefRepository(state: askingDebrief));
      final skip = tester.widget<TextButton>(byKey('debrief-skip'));
      expect(skip.onPressed, isNotNull);
    });
  });

  group('inputs', () {
    testWidgets('a scale is a row of numbered chips with its end labels', (
      tester,
    ) async {
      await pumpCard(tester, FakeDebriefRepository(state: askingDebrief));
      for (var v = 1; v <= 5; v++) {
        expect(byKey('debrief-clear-$v'), findsOneWidget);
        expect(find.text('$v'), findsWidgets);
      }
      expect(byKey('debrief-clear-6'), findsNothing);
      expect(byKey('debrief-clear-first-label'), findsOneWidget);
      expect(
        tester.widget<Text>(byKey('debrief-clear-first-label')).data,
        'Not clear at all',
      );
      expect(
        tester.widget<Text>(byKey('debrief-clear-last-label')).data,
        'Very clear',
      );
      expect(byKey('debrief-clear-chosen'), findsNothing);

      // All chips sit on one row; the end labels sit under the outer chips.
      final first = tester.getRect(byKey('debrief-clear-1'));
      final last = tester.getRect(byKey('debrief-clear-5'));
      expect(last.top, first.top);
      final firstLabel = tester.getRect(byKey('debrief-clear-first-label'));
      final lastLabel = tester.getRect(byKey('debrief-clear-last-label'));
      expect(firstLabel.left, first.left);
      expect(lastLabel.right, last.right);
      expect(firstLabel.top, greaterThan(first.bottom - 1));
      expect(lastLabel.top, greaterThan(last.bottom - 1));
    });

    testWidgets('choosing a scale point selects one chip and shows its label', (
      tester,
    ) async {
      await pumpCard(tester, FakeDebriefRepository(state: askingDebrief));
      await tapKey(tester, 'debrief-clear-2');
      expect(chipSelected(tester, 'debrief-clear-2'), isTrue);
      expect(find.text('Chosen: A little unclear'), findsOneWidget);

      await tapKey(tester, 'debrief-clear-5');
      expect(chipSelected(tester, 'debrief-clear-2'), isFalse);
      expect(chipSelected(tester, 'debrief-clear-5'), isTrue);
      expect(find.text('Chosen: Very clear'), findsOneWidget);
      expect(find.text('Chosen: A little unclear'), findsNothing);
      // The other scale is not touched.
      expect(chipSelected(tester, 'debrief-comfort-5'), isFalse);
    });

    testWidgets('yes/no is two chips, one at a time', (tester) async {
      await pumpCard(tester, FakeDebriefRepository(state: askingDebrief));
      expect(byKey('debrief-uncomfortable-yes'), findsOneWidget);
      expect(byKey('debrief-uncomfortable-no'), findsOneWidget);
      await tapKey(tester, 'debrief-uncomfortable-yes');
      expect(chipSelected(tester, 'debrief-uncomfortable-yes'), isTrue);
      expect(chipSelected(tester, 'debrief-uncomfortable-no'), isFalse);
      await tapKey(tester, 'debrief-uncomfortable-no');
      expect(chipSelected(tester, 'debrief-uncomfortable-yes'), isFalse);
      expect(chipSelected(tester, 'debrief-uncomfortable-no'), isTrue);
    });

    testWidgets('a choice is one chip per option, one at a time', (
      tester,
    ) async {
      await pumpCard(tester, FakeDebriefRepository(state: askingDebrief));
      for (final label in ['Easy', 'Some trouble', 'Hard']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
      }
      await tapKey(tester, 'debrief-setup-option-1');
      expect(chipSelected(tester, 'debrief-setup-option-1'), isTrue);
      await tapKey(tester, 'debrief-setup-option-2');
      expect(chipSelected(tester, 'debrief-setup-option-1'), isFalse);
      expect(chipSelected(tester, 'debrief-setup-option-2'), isTrue);
    });

    testWidgets('a text answer is a multi-line field with a counter', (
      tester,
    ) async {
      await pumpCard(tester, FakeDebriefRepository(state: askingDebrief));
      final field = tester.widget<TextField>(byKey('debrief-what-text'));
      expect(field.maxLength, 1000);
      expect(field.minLines, greaterThan(1));
      expect(field.maxLines, greaterThan(1));
      expect(field.keyboardType, TextInputType.multiline);
      expect(field.textInputAction, TextInputAction.newline);
      expect(find.text('0/1000'), findsNWidgets(2));

      await type(tester, 'debrief-what-text', 'Too bright');
      expect(find.text('10/1000'), findsOneWidget);
      expect(find.text('0/1000'), findsOneWidget);
    });

    testWidgets('a text answer stops at 1000 characters', (tester) async {
      await pumpCard(tester, FakeDebriefRepository(state: askingDebrief));
      await type(tester, 'debrief-what-text', 'a' * 1200);
      expect(find.text('1000/1000'), findsOneWidget);
      final field = tester.widget<TextField>(byKey('debrief-what-text'));
      expect(field.controller!.text.length, 1000);
    });

    testWidgets('Enter in the text field adds a line and sends nothing', (
      tester,
    ) async {
      final repo = FakeDebriefRepository(state: askingDebrief);
      await pumpCard(tester, repo);
      await answerRequired(tester);
      expect(sendEnabled(tester), isTrue);

      await tapKey(tester, 'debrief-what-text');
      await tester.enterText(byKey('debrief-what-text'), 'Line one\nLine two');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.testTextInput.receiveAction(TextInputAction.newline);
      await tester.pumpAndSettle();

      expect(repo.submitted, isEmpty);
      expect(byKey(_card), findsOneWidget);
      final field = tester.widget<TextField>(byKey('debrief-what-text'));
      expect(field.controller!.text, 'Line one\nLine two');
    });

    testWidgets('a chip can be chosen from the keyboard', (tester) async {
      await pumpCard(tester, FakeDebriefRepository(state: askingDebrief));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(chipSelected(tester, 'debrief-clear-2'), isTrue);
    });
  });

  group('keyboard order', () {
    testWidgets('Tab follows the questions from top to bottom', (tester) async {
      await pumpCard(tester, FakeDebriefRepository(state: askingDebrief));
      final expected = [
        for (var v = 1; v <= 5; v++) 'debrief-clear-$v',
        for (var v = 1; v <= 5; v++) 'debrief-comfort-$v',
        'debrief-uncomfortable-yes',
        'debrief-uncomfortable-no',
        'debrief-what-text',
        'debrief-setup-option-0',
        'debrief-setup-option-1',
        'debrief-setup-option-2',
        'debrief-change-text',
        'debrief-skip',
      ];
      final known = expected.toSet();
      final visited = <String?>[];
      for (var i = 0; i < expected.length; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        visited.add(_focusedKey(known));
      }
      expect(visited, expected);
    });
  });

  group('sending', () {
    testWidgets('Send answers posts the version and the answers', (
      tester,
    ) async {
      final repo = FakeDebriefRepository(state: askingDebrief);
      await pumpCard(tester, repo);
      await answerRequired(tester);
      await tapKey(tester, 'debrief-uncomfortable-yes');
      await type(tester, 'debrief-what-text', '  The light was bright.  ');
      await tapKey(tester, 'debrief-setup-option-1');
      await tapKey(tester, 'debrief-send');
      await tester.pumpAndSettle();

      expect(repo.submitted, hasLength(1));
      expect(repo.submitted.single.sessionId, '11');
      expect(repo.lastBody, {
        'form_version': 3,
        'answers': {
          'clear': 4,
          'comfort': 2,
          'uncomfortable': true,
          'what': 'The light was bright.',
          'setup': 'Some trouble',
        },
        'skipped': false,
      });
    });

    testWidgets('unanswered optional questions are left out', (tester) async {
      final repo = FakeDebriefRepository(state: askingDebrief);
      await pumpCard(tester, repo);
      await answerRequired(tester);
      await tapKey(tester, 'debrief-send');
      await tester.pumpAndSettle();
      expect(repo.lastBody['answers'], {
        'clear': 4,
        'comfort': 2,
        'uncomfortable': false,
      });
      expect(repo.lastBody['skipped'], false);
    });

    testWidgets('Skip these questions posts skipped: true and no answers', (
      tester,
    ) async {
      final repo = FakeDebriefRepository(state: askingDebrief);
      await pumpCard(tester, repo);
      // Whatever was chosen so far is not sent.
      await tapKey(tester, 'debrief-clear-3');
      await type(tester, 'debrief-what-text', 'not sent');
      await tapKey(tester, 'debrief-skip');
      await tester.pumpAndSettle();

      expect(repo.submitted, hasLength(1));
      expect(repo.lastBody, {
        'form_version': 3,
        'answers': <String, Object>{},
        'skipped': true,
      });
      expect(byKey('debrief-thanks'), findsOneWidget);
      expect(byKey(_card), findsNothing);
    });

    testWidgets('the buttons wait while sending and it is sent once', (
      tester,
    ) async {
      final repo = FakeDebriefRepository(state: askingDebrief)
        ..gate = Completer();
      await pumpCard(tester, repo);
      await answerRequired(tester);
      await tapKey(tester, 'debrief-send');

      expect(sendEnabled(tester), isFalse);
      expect(
        tester.widget<TextButton>(byKey('debrief-skip')).onPressed,
        isNull,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(byKey('debrief-send'), warnIfMissed: false);
      await tester.pump();

      repo.gate!.complete();
      await tester.pumpAndSettle();
      expect(repo.submitted, hasLength(1));
      expect(byKey('debrief-thanks'), findsOneWidget);
    });
  });

  group('thank-you state', () {
    testWidgets('after sending, the thanks line replaces the form', (
      tester,
    ) async {
      final repo = FakeDebriefRepository(state: askingDebrief);
      await pumpCard(tester, repo);
      await answerRequired(tester);
      await tapKey(tester, 'debrief-send');
      await tester.pumpAndSettle();

      expect(find.text(thanks), findsOneWidget);
      expect(byKey(_card), findsNothing);
      expect(find.text('Send answers'), findsNothing);
      expect(find.text('A few questions about this session'), findsNothing);
    });

    testWidgets('after skipping, a short thanks replaces the form', (
      tester,
    ) async {
      final repo = FakeDebriefRepository(state: askingDebrief);
      await pumpCard(tester, repo);
      await tapKey(tester, 'debrief-skip');
      await tester.pumpAndSettle();
      expect(find.text('Skipped. Thank you.'), findsOneWidget);
      expect(byKey(_card), findsNothing);
    });

    testWidgets('the form never comes back for that session', (tester) async {
      final repo = FakeDebriefRepository(state: askingDebrief);
      await pumpCard(tester, repo);
      await answerRequired(tester);
      await tapKey(tester, 'debrief-send');
      await tester.pumpAndSettle();
      expect(find.text(thanks), findsOneWidget);

      // A new visit to the page: the server now holds the answer.
      await tester.pumpWidget(const SizedBox());
      await pumpCard(tester, repo);
      expect(byKey(_card), findsNothing);
      expect(find.text(thanks), findsNothing);
      expect(repo.loads, ['11', '11']);
    });
  });

  group('server refusals', () {
    testWidgets('409 shows the message as written with a Reload button', (
      tester,
    ) async {
      final repo = FakeDebriefRepository(state: askingDebrief)
        ..submitFailure = const ApiException(changedMessage, statusCode: 409);
      await pumpCard(tester, repo);
      await answerRequired(tester);
      await type(tester, 'debrief-what-text', 'kept text');
      await tapKey(tester, 'debrief-send');
      await tester.pumpAndSettle();

      expect(find.text(changedMessage), findsOneWidget);
      expect(byKey('debrief-reload'), findsOneWidget);
      expect(byKey(_card), findsOneWidget);
      expect(byKey('debrief-thanks'), findsNothing);
      expect(repo.submitted, isEmpty);
    });

    testWidgets('Reload fetches the new questions and keeps matching answers', (
      tester,
    ) async {
      final repo = FakeDebriefRepository(state: askingDebrief)
        ..submitFailure = const ApiException(changedMessage, statusCode: 409);
      await pumpCard(tester, repo);
      await answerRequired(tester);
      await type(tester, 'debrief-what-text', 'kept text');
      await tapKey(tester, 'debrief-send');
      await tester.pumpAndSettle();
      expect(find.text(changedMessage), findsOneWidget);

      // The team changed the form: a reworded scale, a new question and the
      // scale of "comfort" is now 1-3.
      repo
        ..submitFailure = null
        ..state = const SessionDebrief(
          enabled: true,
          sessionEnded: true,
          form: ParticipantDebriefForm(
            version: 4,
            questions: [
              ParticipantDebriefQuestion(
                key: 'clear',
                type: ParticipantDebriefQuestionType.scale,
                prompt: 'How clear was everything?',
                required: true,
                scaleMax: 5,
              ),
              ParticipantDebriefQuestion(
                key: 'comfort',
                type: ParticipantDebriefQuestionType.scale,
                prompt: 'How comfortable was the session?',
                required: true,
                scaleMax: 3,
              ),
              ParticipantDebriefQuestion(
                key: 'uncomfortable',
                type: ParticipantDebriefQuestionType.yesNo,
                prompt: 'Was anything uncomfortable?',
                required: true,
              ),
              ParticipantDebriefQuestion(
                key: 'what',
                type: ParticipantDebriefQuestionType.text,
                prompt: 'What was uncomfortable?',
              ),
              ParticipantDebriefQuestion(
                key: 'again',
                type: ParticipantDebriefQuestionType.yesNo,
                prompt: 'Would you do this again?',
                required: true,
              ),
            ],
          ),
        );
      await tapKey(tester, 'debrief-reload');
      await tester.pumpAndSettle();

      expect(find.text(changedMessage), findsNothing);
      expect(byKey('debrief-reload'), findsNothing);
      expect(find.text('How clear was everything?'), findsOneWidget);
      expect(find.text('Would you do this again?'), findsOneWidget);
      expect(byKey('debrief-setup-option-0'), findsNothing);
      // Answers that still fit stay.
      expect(chipSelected(tester, 'debrief-clear-4'), isTrue);
      expect(chipSelected(tester, 'debrief-comfort-2'), isTrue);
      expect(chipSelected(tester, 'debrief-uncomfortable-no'), isTrue);
      expect(find.text('kept text'), findsOneWidget);
      // The new required question is open.
      expect(sendEnabled(tester), isFalse);

      await tapKey(tester, 'debrief-again-yes');
      await tapKey(tester, 'debrief-send');
      await tester.pumpAndSettle();
      expect(repo.lastBody, {
        'form_version': 4,
        'answers': {
          'clear': 4,
          'comfort': 2,
          'uncomfortable': false,
          'what': 'kept text',
          'again': true,
        },
        'skipped': false,
      });
      expect(find.text(thanks), findsOneWidget);
    });

    testWidgets('a scale answer outside the new range is dropped on reload', (
      tester,
    ) async {
      final repo = FakeDebriefRepository(state: askingDebrief)
        ..submitFailure = const ApiException(changedMessage, statusCode: 409);
      await pumpCard(tester, repo);
      await tapKey(tester, 'debrief-clear-5');
      await answerRequired(tester);
      await tapKey(tester, 'debrief-clear-5');
      await tapKey(tester, 'debrief-send');
      await tester.pumpAndSettle();

      repo
        ..submitFailure = null
        ..state = const SessionDebrief(
          enabled: true,
          sessionEnded: true,
          form: ParticipantDebriefForm(
            version: 4,
            questions: [
              ParticipantDebriefQuestion(
                key: 'clear',
                type: ParticipantDebriefQuestionType.scale,
                prompt: 'Clear?',
                required: true,
                scaleMax: 3,
              ),
            ],
          ),
        );
      await tapKey(tester, 'debrief-reload');
      await tester.pumpAndSettle();
      expect(chipSelected(tester, 'debrief-clear-3'), isFalse);
      expect(sendEnabled(tester), isFalse);
    });

    testWidgets('409 because it was already answered ends with no card', (
      tester,
    ) async {
      final repo = FakeDebriefRepository(state: askingDebrief)
        ..submitFailure = const ApiException(
          'already answered',
          statusCode: 409,
        );
      await pumpCard(tester, repo);
      await answerRequired(tester);
      await tapKey(tester, 'debrief-send');
      await tester.pumpAndSettle();
      expect(find.text('already answered'), findsOneWidget);

      repo.state = const SessionDebrief(
        enabled: true,
        sessionEnded: true,
        form: debriefForm3,
        answer: DebriefAnswer(formVersion: 3),
      );
      await tapKey(tester, 'debrief-reload');
      await tester.pumpAndSettle();
      expect(byKey(_card), findsNothing);
    });

    testWidgets('a failing Reload keeps the message and the button', (
      tester,
    ) async {
      final repo = FakeDebriefRepository(state: askingDebrief)
        ..submitFailure = const ApiException(changedMessage, statusCode: 409);
      await pumpCard(tester, repo);
      await answerRequired(tester);
      await tapKey(tester, 'debrief-send');
      await tester.pumpAndSettle();

      repo.loadFailure = const ApiException(
        'Could not reach the server. Check your connection and try again.',
      );
      await tapKey(tester, 'debrief-reload');
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not reach the server'), findsOneWidget);
      expect(byKey('debrief-reload'), findsOneWidget);
      expect(chipSelected(tester, 'debrief-clear-4'), isTrue);
    });

    testWidgets('422 shows the message as written and lets the person retry', (
      tester,
    ) async {
      const message = 'Please answer "How clear were the instructions?".';
      final repo = FakeDebriefRepository(state: askingDebrief)
        ..submitFailure = const ApiException(message, statusCode: 422);
      await pumpCard(tester, repo);
      await answerRequired(tester);
      await tapKey(tester, 'debrief-send');
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(byKey('debrief-reload'), findsNothing);
      expect(byKey(_card), findsOneWidget);
      expect(sendEnabled(tester), isTrue);
      expect(chipSelected(tester, 'debrief-clear-4'), isTrue);

      // The error can be dismissed, and a retry goes through.
      repo.submitFailure = null;
      await tapKey(tester, 'debrief-send');
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
      expect(find.text(thanks), findsOneWidget);
    });

    testWidgets('a network failure is shown and can be retried', (
      tester,
    ) async {
      final repo = FakeDebriefRepository(state: askingDebrief)
        ..submitFailure = const ApiException(
          'Could not reach the server. Check your connection and try again.',
        );
      await pumpCard(tester, repo);
      await answerRequired(tester);
      await tapKey(tester, 'debrief-send');
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not reach the server'), findsOneWidget);
      expect(byKey('debrief-reload'), findsNothing);
      expect(sendEnabled(tester), isTrue);
    });

    testWidgets('a refused skip shows the message too', (tester) async {
      final repo = FakeDebriefRepository(state: askingDebrief)
        ..submitFailure = const ApiException(changedMessage, statusCode: 409);
      await pumpCard(tester, repo);
      await tapKey(tester, 'debrief-skip');
      await tester.pumpAndSettle();
      expect(find.text(changedMessage), findsOneWidget);
      expect(byKey('debrief-reload'), findsOneWidget);
    });
  });

  group('layout', () {
    const wide = SessionDebrief(
      enabled: true,
      sessionEnded: true,
      form: ParticipantDebriefForm(
        version: 1,
        questions: [
          ParticipantDebriefQuestion(
            key: 'ten',
            type: ParticipantDebriefQuestionType.scale,
            prompt:
                'How comfortable was the whole session from start to end, '
                'including the parts where the face was shown?',
            required: true,
            scaleMax: 10,
            labels: [
              'Not comfortable at all',
              '2',
              '3',
              '4',
              '5',
              '6',
              '7',
              '8',
              '9',
              'Completely comfortable, no problems at all',
            ],
          ),
          ParticipantDebriefQuestion(
            key: 'five',
            type: ParticipantDebriefQuestionType.scale,
            prompt: 'How clear were the instructions?',
            scaleMax: 5,
            labels: ['Very unclear', '', '', '', 'Very clear'],
          ),
          ParticipantDebriefQuestion(
            key: 'yn',
            type: ParticipantDebriefQuestionType.yesNo,
            prompt: 'Was anything uncomfortable?',
            required: true,
          ),
          ParticipantDebriefQuestion(
            key: 'pick',
            type: ParticipantDebriefQuestionType.choice,
            prompt: 'Which part was hardest?',
            options: [
              'The camera setup and the lighting in my room',
              'The dots',
              'The faces',
              'A very long option that goes on and on to check that a single '
                  'chip wraps inside a phone-sized card instead of overflowing',
            ],
          ),
          ParticipantDebriefQuestion(
            key: 'free',
            type: ParticipantDebriefQuestionType.text,
            prompt: 'Anything else you want to tell us about the session?',
          ),
        ],
      ),
    );

    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets('no overflow at ${width.toInt()} px', (tester) async {
        final repo = FakeDebriefRepository(state: wide)
          ..submitFailure = const ApiException(
            '$changedMessage - this message is deliberately long so that it '
            'has to wrap inside the banner on a phone',
            statusCode: 409,
          );
        await pumpCard(tester, repo, width: width, height: 900);
        expect(byKey(_card), findsOneWidget);

        await tapKey(tester, 'debrief-ten-7');
        await tapKey(tester, 'debrief-yn-yes');
        await tapKey(tester, 'debrief-pick-option-3');
        await type(tester, 'debrief-free-text', 'Some words\nover two lines');
        await tapKey(tester, 'debrief-send');
        await tester.pumpAndSettle();
        expect(byKey('debrief-reload'), findsOneWidget);

        final card = tester.getRect(byKey(_card));
        expect(card.right, lessThanOrEqualTo(width));
        for (final key in [
          for (var v = 1; v <= 10; v++) 'debrief-ten-$v',
          for (var v = 1; v <= 5; v++) 'debrief-five-$v',
          'debrief-yn-yes',
          'debrief-yn-no',
          for (var i = 0; i < 4; i++) 'debrief-pick-option-$i',
          'debrief-send',
          'debrief-skip',
          'debrief-reload',
        ]) {
          final rect = tester.getRect(byKey(key));
          expect(rect.left, greaterThanOrEqualTo(card.left), reason: key);
          expect(rect.right, lessThanOrEqualTo(card.right), reason: key);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'ten chips stay on one row on wide screens and wrap on a phone',
      (tester) async {
        await pumpCard(
          tester,
          FakeDebriefRepository(state: wide),
          width: 800,
          height: 900,
        );
        var first = tester.getRect(byKey('debrief-ten-1'));
        var last = tester.getRect(byKey('debrief-ten-10'));
        expect(last.top, first.top);
        final firstLabel = tester.getRect(byKey('debrief-ten-first-label'));
        final lastLabel = tester.getRect(byKey('debrief-ten-last-label'));
        expect(firstLabel.left, first.left);
        expect(lastLabel.right, last.right);

        await pumpCard(
          tester,
          FakeDebriefRepository(state: wide),
          width: 360,
          height: 900,
        );
        first = tester.getRect(byKey('debrief-ten-1'));
        last = tester.getRect(byKey('debrief-ten-10'));
        expect(last.top, greaterThan(first.top));
        // Chips stay big enough to tap.
        expect(first.width, greaterThanOrEqualTo(36));
        expect(first.height, greaterThanOrEqualTo(36));
        // Five points still fit on one row on a phone.
        final f1 = tester.getRect(byKey('debrief-five-1'));
        final f5 = tester.getRect(byKey('debrief-five-5'));
        expect(f5.top, f1.top);
      },
    );

    testWidgets('the form scrolls on a short screen', (tester) async {
      await pumpCard(
        tester,
        FakeDebriefRepository(state: askingDebrief),
        width: 360,
        height: 480,
      );
      await tapKey(tester, 'debrief-skip');
      await tester.pumpAndSettle();
      expect(byKey('debrief-thanks'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('models and wire', () {
    test('a form skips questions of a type this app does not know', () {
      final form = ParticipantDebriefForm.fromJson({
        'version': 2,
        'enabled': true,
        'questions': [
          {
            'key': 'a',
            'type': 'scale',
            'prompt': 'A',
            'required': true,
            'scale_max': 4,
          },
          {'key': 'b', 'type': 'slider', 'prompt': 'B'},
          {'type': 'text', 'prompt': 'no key'},
          {
            'key': 'c',
            'type': 'choice',
            'prompt': 'C',
            'options': ['x', 'y'],
          },
        ],
        'saved': true,
      });
      expect(form.version, 2);
      expect([for (final q in form.questions) q.key], ['a', 'c']);
      expect(form.questions.first.required, isTrue);
      expect(form.questions.first.scaleMax, 4);
      expect(form.questions.last.options, ['x', 'y']);
    });

    test('a scale answer must be within 1..scale_max', () {
      const q = ParticipantDebriefQuestion(
        key: 's',
        type: ParticipantDebriefQuestionType.scale,
        prompt: 'S',
        scaleMax: 5,
      );
      expect(q.accepts(0), isFalse);
      expect(q.accepts(1), isTrue);
      expect(q.accepts(5), isTrue);
      expect(q.accepts(6), isFalse);
      expect(q.accepts('3'), isFalse);
      expect(q.accepts(true), isFalse);
    });

    test('the offer needs enabled, an ended session, a form and no answer', () {
      SessionDebrief make({
        bool enabled = true,
        bool ended = true,
        ParticipantDebriefForm? form = debriefForm3,
        DebriefAnswer? answer,
      }) => SessionDebrief(
        enabled: enabled,
        sessionEnded: ended,
        form: form,
        answer: answer,
      );
      expect(make().shouldAsk, isTrue);
      expect(make(enabled: false).shouldAsk, isFalse);
      expect(make(ended: false).shouldAsk, isFalse);
      expect(make(form: null).shouldAsk, isFalse);
      expect(
        make(form: const ParticipantDebriefForm(version: 1)).shouldAsk,
        isFalse,
      );
      expect(
        make(answer: const DebriefAnswer(formVersion: 3, skipped: true))
            .shouldAsk,
        isFalse,
      );
    });

    test('the repository reads the debrief and posts the answer', () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        baseUrl: 'http://api.test:8000',
        tokenStore: TokenStore()..save('tok'),
        httpClient: MockClient((request) async {
          requests.add(request);
          final headers = {'content-type': 'application/json'};
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'enabled': true,
                'session_ended': true,
                'form': {
                  'version': 3,
                  'enabled': true,
                  'saved': true,
                  'questions': [
                    {
                      'key': 'clear',
                      'type': 'scale',
                      'prompt': 'How clear?',
                      'required': true,
                      'scale_max': 5,
                      'labels': ['a', 'b', 'c', 'd', 'e'],
                    },
                  ],
                },
                'answer': null,
              }),
              200,
              headers: headers,
            );
          }
          return http.Response(
            jsonEncode({
              'form_version': 3,
              'answers': {'clear': 4, 'ok': true, 'what': 'x'},
              'skipped': false,
              'created_at': '2026-09-30T10:00:00',
            }),
            201,
            headers: headers,
          );
        }),
      );
      final repo = ApiDebriefRepository(api);

      final state = await repo.load('11');
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/me/sessions/11/debrief');
      expect(requests.single.headers['Authorization'], 'Bearer tok');
      expect(state.shouldAsk, isTrue);
      expect(state.form!.questions.single.labels, hasLength(5));

      final stored = await repo.submit(
        '11',
        const DebriefAnswer(formVersion: 3, answers: {'clear': 4}),
      );
      expect(requests.last.method, 'POST');
      expect(requests.last.url.path, '/me/sessions/11/debrief');
      expect(jsonDecode(requests.last.body), {
        'form_version': 3,
        'answers': {'clear': 4},
        'skipped': false,
      });
      expect(stored.formVersion, 3);
      expect(stored.answers, {'clear': 4, 'ok': true, 'what': 'x'});
      expect(stored.createdAt, '2026-09-30T10:00:00');
    });

    test(
      'the repository passes the server message on a 409 and a 422',
      () async {
        Future<ApiException> post(int status, String detail) async {
          final api = ApiClient(
            baseUrl: 'http://api.test:8000',
            httpClient: MockClient(
              (_) async => http.Response(
                jsonEncode({'detail': detail}),
                status,
                headers: {'content-type': 'application/json'},
              ),
            ),
          );
          try {
            await ApiDebriefRepository(
              api,
            ).submit('11', const DebriefAnswer(formVersion: 3, skipped: true));
          } on ApiException catch (e) {
            return e;
          }
          fail('expected an ApiException');
        }

        final conflict = await post(409, changedMessage);
        expect(conflict.statusCode, 409);
        expect(conflict.message, changedMessage);
        final invalid = await post(422, 'answer "clear" is required');
        expect(invalid.statusCode, 422);
        expect(invalid.message, 'answer "clear" is required');
      },
    );
  });

  group('on the session summary', () {
    Future<Rig> endedRig(WidgetTester tester) async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await tester.runAsync(() async {
        await rig.toCameraCheck();
        await rig.controller.endEarly();
      });
      return rig;
    }

    Future<void> pumpFlowWith(WidgetTester tester, Rig rig, TestBed bed) async {
      await tester.pumpWidget(
        AppScope(
          dependencies: bed.dependencies,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  key: const Key('open-flow'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          SessionFlowScreen(controller: rig.controller),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(byKey('open-flow'));
      await tester.pumpAndSettle();
    }

    testWidgets('the card appears after the summary of an ended session', (
      tester,
    ) async {
      useWindow(tester, 800, 900);
      final rig = await endedRig(tester);
      final bed = TestBed(debrief: FakeDebriefRepository(state: askingDebrief));
      await pumpFlowWith(tester, rig, bed);

      expect(find.text('Session summary'), findsOneWidget);
      expect(byKey(_card), findsOneWidget);
      expect(bed.debrief.loads, ['11']);
      // The card comes after the numbers and before the way home.
      final summaryTop = tester
          .getTopLeft(find.text('How much could be used'))
          .dy;
      final cardTop = tester.getTopLeft(byKey(_card)).dy;
      final homeTop = tester.getTopLeft(byKey('summary-home')).dy;
      expect(cardTop, greaterThan(summaryTop));
      expect(homeTop, greaterThan(cardTop));
    });

    testWidgets('no card when the study has the debrief off', (tester) async {
      useWindow(tester, 800, 900);
      final rig = await endedRig(tester);
      final bed = TestBed(); // disabled by default
      await pumpFlowWith(tester, rig, bed);
      expect(find.text('Session summary'), findsOneWidget);
      expect(byKey(_card), findsNothing);
      expect(find.text('Back to home'), findsOneWidget);
    });

    testWidgets('the card never blocks leaving the summary', (tester) async {
      useWindow(tester, 800, 900);
      final rig = await endedRig(tester);
      final bed = TestBed(debrief: FakeDebriefRepository(state: askingDebrief));
      await pumpFlowWith(tester, rig, bed);
      expect(byKey(_card), findsOneWidget);
      expect(sendEnabled(tester), isFalse);

      // Half answered, required questions open: Back to home still leaves.
      await tapKey(tester, 'debrief-clear-4');
      await tapKey(tester, 'summary-home');
      await tester.pumpAndSettle();
      expect(find.text('Session summary'), findsNothing);
      expect(byKey('open-flow'), findsOneWidget);
      expect(bed.debrief.submitted, isEmpty);
    });

    testWidgets(
      'what was typed survives a refresh and scrolling on a short screen',
      (tester) async {
        useWindow(tester, 360, 300);
        final rig = await endedRig(tester);
        final bed = TestBed(
          debrief: FakeDebriefRepository(state: askingDebrief),
        );
        await pumpFlowWith(tester, rig, bed);

        await tapKey(tester, 'debrief-clear-4');
        await type(tester, 'debrief-what-text', 'Still here');
        // A field that has focus is kept alive by Flutter; without focus only
        // the page building all of its children keeps the card's state.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();

        // The summary is reloaded (Try again path) and the page scrolls away.
        await tester.runAsync(rig.controller.reloadSummary);
        await tester.pump();
        await tester.drag(find.byType(ListView).first, const Offset(0, 4000));
        await tester.pumpAndSettle();

        expect(byKey(_card), findsOneWidget);
        expect(chipSelected(tester, 'debrief-clear-4'), isTrue);
        expect(
          tester.widget<TextField>(byKey('debrief-what-text')).controller!.text,
          'Still here',
        );
        expect(bed.debrief.loads, ['11']);
      },
    );

    testWidgets('sending from the summary shows the thanks line', (
      tester,
    ) async {
      useWindow(tester, 800, 900);
      final rig = await endedRig(tester);
      final bed = TestBed(debrief: FakeDebriefRepository(state: askingDebrief));
      await pumpFlowWith(tester, rig, bed);
      await answerRequired(tester);
      await tapKey(tester, 'debrief-send');
      await tester.pumpAndSettle();
      expect(find.text(thanks), findsOneWidget);
      expect(find.text('Back to home'), findsOneWidget);
      expect(bed.debrief.lastBody['form_version'], 3);
    });

    for (final width in [360.0, 800.0, 1440.0]) {
      testWidgets(
        'summary with the card has no overflow at ${width.toInt()} px',
        (tester) async {
          useWindow(tester, width, width == 360 ? 640 : 900);
          final rig = await endedRig(tester);
          final bed = TestBed(
            debrief: FakeDebriefRepository(state: askingDebrief),
          );
          await pumpFlowWith(tester, rig, bed);
          expect(byKey(_card), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}

/// The known key of the widget that holds the keyboard focus, if any.
String? _focusedKey(Set<String> known) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  String? found;
  context.visitAncestorElements((element) {
    final key = element.widget.key;
    if (key is ValueKey<String> && known.contains(key.value)) {
      found = key.value;
      return false;
    }
    return true;
  });
  return found;
}
