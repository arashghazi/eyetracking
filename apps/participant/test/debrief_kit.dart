import 'dart:async';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:participant_app/features/debrief/domain/debrief_models.dart';
import 'package:participant_app/features/debrief/domain/debrief_repository.dart';

/// Three required questions, then optional ones; every question type.
const debriefQuestions = [
  ParticipantDebriefQuestion(
    key: 'clear',
    type: ParticipantDebriefQuestionType.scale,
    prompt: 'How clear were the instructions?',
    required: true,
    scaleMax: 5,
    labels: [
      'Not clear at all',
      'A little unclear',
      'Neutral',
      'Fairly clear',
      'Very clear',
    ],
  ),
  ParticipantDebriefQuestion(
    key: 'comfort',
    type: ParticipantDebriefQuestionType.scale,
    prompt: 'How comfortable was the session?',
    required: true,
    scaleMax: 5,
    labels: [
      'Very uncomfortable',
      'Uncomfortable',
      'Neutral',
      'Comfortable',
      'Very comfortable',
    ],
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
    key: 'setup',
    type: ParticipantDebriefQuestionType.choice,
    prompt: 'How easy was the camera setup?',
    options: ['Easy', 'Some trouble', 'Hard'],
  ),
  ParticipantDebriefQuestion(
    key: 'change',
    type: ParticipantDebriefQuestionType.text,
    prompt: 'What one thing would you change?',
  ),
];

const debriefForm3 = ParticipantDebriefForm(
  version: 3,
  questions: debriefQuestions,
);

/// The server has questions to ask about an ended session.
const askingDebrief = SessionDebrief(
  enabled: true,
  sessionEnded: true,
  form: debriefForm3,
);

/// A study that has not switched the debrief on.
const disabledDebrief = SessionDebrief(
  enabled: false,
  sessionEnded: true,
  form: ParticipantDebriefForm(
    version: 3,
    enabled: false,
    questions: debriefQuestions,
  ),
);

/// In-memory stand-in for `/me/sessions/{sid}/debrief`.
class FakeDebriefRepository implements DebriefRepository {
  FakeDebriefRepository({this.state = disabledDebrief});

  SessionDebrief state;

  /// Thrown by [load] / [submit] when set.
  ApiException? loadFailure;
  ApiException? submitFailure;

  /// When set, [submit] waits for it (to test the sending state).
  Completer<void>? gate;

  final List<String> loads = [];
  final List<({String sessionId, DebriefAnswer answer})> submitted = [];

  Map<String, dynamic> get lastBody => submitted.last.answer.toJson();

  @override
  Future<SessionDebrief> load(String sessionId) async {
    loads.add(sessionId);
    if (loadFailure != null) throw loadFailure!;
    return state;
  }

  @override
  Future<DebriefAnswer> submit(String sessionId, DebriefAnswer answer) async {
    await gate?.future;
    if (submitFailure != null) throw submitFailure!;
    submitted.add((sessionId: sessionId, answer: answer));
    final stored = DebriefAnswer(
      formVersion: answer.formVersion,
      answers: answer.answers,
      skipped: answer.skipped,
      createdAt: '2026-09-30T10:00:00',
    );
    state = SessionDebrief(
      enabled: state.enabled,
      sessionEnded: state.sessionEnded,
      form: state.form,
      answer: stored,
    );
    return stored;
  }
}
