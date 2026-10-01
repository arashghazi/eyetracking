import 'dart:async';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:participant_app/features/session/domain/live_repository.dart';

/// Face, eye and mouth regions as fractions of the avatar frame.
const liveFaceLayout = NormalizedFaceLayout(
  faceBox: Box(0.3, 0.1, 0.4, 0.8),
  eyeRegion: Box(0.3, 0.25, 0.4, 0.2),
  mouthRegion: Box(0.3, 0.55, 0.4, 0.25),
);

/// [actual] equals [expected] to within a hundredth of a pixel.
void expectBox(Box actual, Box expected, {String? reason}) {
  expect(actual.x, closeTo(expected.x, 0.01), reason: reason);
  expect(actual.y, closeTo(expected.y, 0.01), reason: reason);
  expect(actual.w, closeTo(expected.w, 0.01), reason: reason);
  expect(actual.h, closeTo(expected.h, 0.01), reason: reason);
}

/// The development avatar as the service describes it, with the video
/// address already resolved.
const liveAvatarUrl = 'http://api.test:8000/static/live/sample-face.webm';

/// In-memory stand-in for the step 7 `live` endpoints: it keeps one
/// conversation, answers typed and spoken turns with a canned reply, ends at
/// the turn limit, refuses a wrong `expect_turn` with a 409 like the server,
/// and records every call so tests can read what the app sent.
class FakeLiveRepository implements LiveRepository {
  FakeLiveRepository({
    this.maxTurns = 4,
    this.inputModes = const [LiveInputMode.typed, LiveInputMode.speech],
    this.storeTranscriptOffered = false,
    this.faceLayout = liveFaceLayout,
    this.openingLine = 'Hi Sam! What do you like most about trains?',
    this.closingLine = 'Thank you for talking with me about trains.',
    this.syntheticAvatar = true,
    this.videoUrl = liveAvatarUrl,
    this.maxChars = 400,
    this.topic = 'trains',
  });

  final int maxTurns;
  final List<LiveInputMode> inputModes;
  final bool storeTranscriptOffered;
  NormalizedFaceLayout? faceLayout;
  final String openingLine;
  final String closingLine;
  final bool syntheticAvatar;
  String? videoUrl;
  final int maxChars;
  final String topic;

  // Behaviour switches.
  ApiException? snapshotFailure;
  ApiException? startFailure;
  ApiException? endFailure;

  /// Failures handed out one per turn request, oldest first.
  final List<ApiException> turnFailures = [];

  /// Results handed out in order; when empty the canned reply answers.
  final List<LiveTurnResult> scripted = [];

  /// Held requests wait for this before they answer (a turn in flight).
  Completer<void>? gate;

  /// What a spoken turn is heard as.
  String heard = 'I like steam trains';

  /// The closing turn comes without its text (a transcript that is not kept).
  bool closingWithoutText = false;

  /// The next canned reply flags the participant's message as distressed.
  bool distressOnNext = false;

  // What the app sent.
  final List<String> calls = [];
  final List<({LiveInputMode mode, bool allowTranscript, int? tMs})> starts = [];
  final List<({int expectTurn, String text, int? tMs})> typed = [];
  final List<({int expectTurn, AudioClip clip, int? tMs})> audio = [];
  int endCalls = 0;

  LiveConversation? conversation;
  final List<LiveTurn> turns = [];

  LiveLimits get limits => LiveLimits(
        maxTurns: maxTurns,
        maxParticipantChars: maxChars,
        inputModes: inputModes,
      );

  /// Opens a conversation as if the participant had started it earlier.
  void seedOpen({
    LiveInputMode mode = LiveInputMode.typed,
    int used = 0,
    bool allowTranscript = false,
  }) {
    conversation = LiveConversation(
      id: '9',
      topic: topic,
      inputMode: mode,
      transcriptAllowed: allowTranscript,
      turnsUsed: used,
      turnsLeft: maxTurns - used,
    );
    turns
      ..clear()
      ..add(_avatar(0, openingLine, const ['scripted_line', 'opening']));
    for (var i = 0; i < used; i++) {
      turns
        ..add(_participant(turns.length, 'message ${i + 1}'))
        ..add(_avatar(turns.length, 'Reply ${i + 1}', const []));
    }
  }

  /// Closes the conversation as the server does when it ends.
  void seedClosed({String reason = LiveEndReason.participantEnded}) {
    seedOpen(used: 1);
    _close(reason);
  }

  LiveTurn _avatar(int index, String? text, List<String> flags) => LiveTurn(
        index: index,
        role: 'avatar',
        text: text,
        chars: text?.length ?? 0,
        flags: flags,
      );

  LiveTurn _participant(int index, String? text, [List<String>? flags]) =>
      LiveTurn(
        index: index,
        role: 'participant',
        text: text,
        chars: text?.length ?? 0,
        flags: flags ?? const ['typed'],
      );

  void _close(String reason) {
    final c = conversation!;
    conversation = LiveConversation(
      id: c.id,
      status: ConversationStatus.closed,
      topic: c.topic,
      inputMode: c.inputMode,
      transcriptAllowed: c.transcriptAllowed,
      turnsUsed: c.turnsUsed,
      turnsLeft: 0,
      endReason: reason,
    );
    if (!c.transcriptAllowed) {
      for (var i = 0; i < turns.length; i++) {
        final t = turns[i];
        turns[i] = LiveTurn(
          index: t.index,
          role: t.role,
          chars: t.chars,
          flags: t.flags,
        );
      }
    }
  }

  LiveConversation _bump() {
    final c = conversation!;
    return conversation = LiveConversation(
      id: c.id,
      topic: c.topic,
      inputMode: c.inputMode,
      transcriptAllowed: c.transcriptAllowed,
      turnsUsed: c.turnsUsed + 1,
      turnsLeft: maxTurns - c.turnsUsed - 1,
    );
  }

  LiveAvatar get _avatarConfig => LiveAvatar(
        videoUrl: videoUrl,
        synthetic: syntheticAvatar,
        note: syntheticAvatar ? 'Development avatar' : null,
      );

  @override
  Future<LiveSnapshot> snapshot(String sessionId) async {
    calls.add('snapshot');
    if (snapshotFailure != null) throw snapshotFailure!;
    return LiveSnapshot(
      conversation: conversation,
      turns: List.of(turns),
      limits: limits,
      storeTranscriptOffered: storeTranscriptOffered,
      inputModes: inputModes,
    );
  }

  @override
  Future<LiveStart> start(
    String sessionId, {
    required LiveInputMode mode,
    required bool allowTranscript,
    int? tMs,
  }) async {
    calls.add('start');
    if (startFailure != null) throw startFailure!;
    starts.add((mode: mode, allowTranscript: allowTranscript, tMs: tMs));
    final existing = conversation;
    if (existing != null) {
      if (existing.isClosed) {
        throw const ApiException('this conversation has ended', statusCode: 409);
      }
      return LiveStart(
        conversation: existing,
        turns: List.of(turns),
        avatar: _avatarConfig,
        faceLayout: faceLayout,
        limits: limits,
        resumed: true,
      );
    }
    seedOpen(
      mode: mode,
      allowTranscript: storeTranscriptOffered && allowTranscript,
    );
    return LiveStart(
      conversation: conversation!,
      turns: List.of(turns),
      avatar: _avatarConfig,
      faceLayout: faceLayout,
      limits: limits,
    );
  }

  Future<LiveTurnResult> _answer(
    int expectTurn,
    String text,
    List<String> flags,
  ) async {
    final held = gate;
    if (held != null) await held.future;
    if (turnFailures.isNotEmpty) throw turnFailures.removeAt(0);
    final c = conversation;
    if (c == null || c.isClosed) {
      throw const ApiException('this conversation has ended', statusCode: 409);
    }
    if (expectTurn != c.turnsUsed) {
      throw const ApiException(
        'this turn was already sent; reload the conversation',
        statusCode: 409,
      );
    }
    if (scripted.isNotEmpty) {
      final r = scripted.removeAt(0);
      _bump();
      turns.addAll([
        if (r.participant != null) r.participant!,
        r.avatar,
      ]);
      if (r.done) _close(r.endReason ?? LiveEndReason.turnLimit);
      return r;
    }
    final next = _bump();
    final distress = distressOnNext;
    distressOnNext = false;
    final part = _participant(turns.length, text, [...flags, 'participant_on_topic']);
    turns.add(part);
    final done = next.turnsUsed >= maxTurns;
    final reply = done
        ? closingLine
        : distress
            ? 'Thank you for telling me. Would you like to pause for a moment?'
            : 'Reply ${next.turnsUsed}: tell me more about $topic.';
    final avatarTurn = _avatar(
      turns.length,
      reply,
      done ? const ['scripted_line', 'closing', 'turn_limit'] : const [],
    );
    turns.add(avatarTurn);
    if (done) _close(LiveEndReason.turnLimit);
    return LiveTurnResult(
      participant: part,
      avatar: done && closingWithoutText
          ? _avatar(avatarTurn.index, null, avatarTurn.flags)
          : avatarTurn,
      turnsUsed: next.turnsUsed,
      turnsLeft: next.turnsLeft,
      done: done,
      endReason: done ? LiveEndReason.turnLimit : null,
      distress: distress,
    );
  }

  @override
  Future<LiveTurnResult> sendTurn(
    String sessionId, {
    required int expectTurn,
    required String text,
    int? tMs,
  }) async {
    calls.add('turn');
    typed.add((expectTurn: expectTurn, text: text, tMs: tMs));
    return _answer(expectTurn, text, const ['typed']);
  }

  @override
  Future<LiveTurnResult> sendAudio(
    String sessionId, {
    required int expectTurn,
    required AudioClip clip,
    int? tMs,
  }) async {
    calls.add('turn-audio');
    audio.add((expectTurn: expectTurn, clip: clip, tMs: tMs));
    return _answer(expectTurn, heard, const ['speech', 'sample_speech']);
  }

  @override
  Future<LiveEndResult> end(String sessionId, {int? tMs}) async {
    calls.add('end');
    endCalls++;
    final held = gate;
    if (held != null) await held.future;
    if (endFailure != null) throw endFailure!;
    final c = conversation;
    if (c == null || c.isClosed) {
      throw const ApiException('this conversation has ended', statusCode: 409);
    }
    final line = _avatar(
      turns.length,
      closingLine,
      const ['scripted_line', 'closing', 'participant_ended'],
    );
    turns.add(line);
    _close(LiveEndReason.participantEnded);
    return LiveEndResult(
      avatar: closingWithoutText ? _avatar(line.index, null, line.flags) : line,
      turnsUsed: c.turnsUsed,
      done: true,
      endReason: LiveEndReason.participantEnded,
    );
  }
}
