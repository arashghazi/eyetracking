import 'dart:async';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/live_practice_controller.dart';

/// Window width from which the conversation panel sits beside the video (and
/// from which the text field takes the keyboard on its own).
const double kLiveWideWidth = 900;

/// The text field of the conversation: Enter sends, Shift+Enter starts a new
/// line, and a counter shows how much of the longest message is used. The
/// field is off while a turn is on its way to the server, and the text stays
/// when the server refuses it.
class LiveTypedInput extends StatefulWidget {
  const LiveTypedInput({super.key, required this.controller});

  final LivePracticeController controller;

  @override
  State<LiveTypedInput> createState() => _LiveTypedInputState();
}

class _LiveTypedInputState extends State<LiveTypedInput> {
  late final TextEditingController _text =
      TextEditingController(text: widget.controller.draft);
  final _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final c = widget.controller;
    final line = _text.text;
    if (line.trim().isEmpty || !c.canSend) return;
    final taken = await c.send(line);
    if (!mounted || !taken) return;
    _text.clear();
    c.setDraft('');
    // The field is switched off while the turn is in flight; take the
    // keyboard back once it is on again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final enter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!enter || HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    unawaited(_send());
    return KeyEventResult.handled;
  }

  late int _focusTicket = widget.controller.inputFocusTicket;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final canSend = c.canSend;
    if (c.inputFocusTicket != _focusTicket) {
      _focusTicket = c.inputFocusTicket;
      // The button that had the browser's focus is gone. The framework may
      // still count this field as focused, so a plain request would do
      // nothing on the web: let go first, then take the focus back.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_focus.hasFocus) {
          _focus.requestFocus();
          return;
        }
        _focus.unfocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focus.requestFocus();
        });
        WidgetsBinding.instance.scheduleFrame();
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  key: const Key('live-input'),
                  controller: _text,
                  focusNode: _focus,
                  // With a keyboard at hand the participant can start typing
                  // at once; on a phone the keyboard would cover the video.
                  autofocus: MediaQuery.sizeOf(context).width >= kLiveWideWidth,
                  enabled: canSend,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: c.limits.maxParticipantChars,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: c.busy ? 'Waiting for the reply...' : 'Type your message',
                    isDense: true,
                  ),
                  onChanged: (value) {
                    c.setDraft(value);
                    setState(() {});
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: FilledButton(
                key: const Key('live-send'),
                onPressed:
                    canSend && _text.text.trim().isNotEmpty ? _send : null,
                child: const Text('Send'),
              ),
            ),
          ],
        ),
        if (c.speechMode)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('live-speak-instead'),
              onPressed: c.busy ? null : c.speakInstead,
              icon: const Icon(Icons.mic_none, size: 18),
              label: const Text('Speak instead'),
            ),
          ),
      ],
    );
  }
}

/// The spoken input: a push-to-talk button (hold it while you talk, or tap
/// once to start and once to stop) and "Type instead".
class LiveSpeechInput extends StatelessWidget {
  const LiveSpeechInput({super.key, required this.controller});

  final LivePracticeController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PushToTalkButton(controller: c),
        const SizedBox(height: 4),
        Text(
          c.recording ? 'Release or tap to send' : 'Tap to start, tap to stop',
          key: const Key('live-talk-hint'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('live-type-instead'),
            onPressed: c.busy ? null : c.typeInstead,
            icon: const Icon(Icons.keyboard_outlined, size: 18),
            label: const Text('Type instead'),
          ),
        ),
      ],
    );
  }
}

/// Push to talk. Pressing starts the recording. Letting go after holding
/// longer than [holdAfter] ends it and sends it; a short tap leaves it
/// running until the next tap. The keyboard (Enter or Space) and screen
/// readers act as a tap, so no one has to hold anything.
class PushToTalkButton extends StatefulWidget {
  const PushToTalkButton({super.key, required this.controller});

  final LivePracticeController controller;

  /// A press longer than this counts as holding.
  static const holdAfter = Duration(milliseconds: 450);

  @override
  State<PushToTalkButton> createState() => _PushToTalkButtonState();
}

class _PushToTalkButtonState extends State<PushToTalkButton> {
  Timer? _holdTimer;
  bool _held = false;
  bool _startedByPress = false;
  bool _focused = false;

  LivePracticeController get _c => widget.controller;
  bool get _active => _c.recording || _c.startingRecording;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _down(PointerDownEvent event) {
    _held = false;
    if (_active) {
      // The second tap of tap-to-start, tap-to-stop.
      _startedByPress = false;
      return;
    }
    if (!_c.canSend) return;
    _startedByPress = true;
    _holdTimer?.cancel();
    _holdTimer = Timer(PushToTalkButton.holdAfter, () => _held = true);
    unawaited(_c.startRecording());
  }

  void _up(PointerEvent event) {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (_startedByPress) {
      // Held and let go: that is the end of what was said. A short tap
      // leaves the recording on.
      if (_held) unawaited(_c.stopRecording());
    } else if (_active) {
      unawaited(_c.stopRecording());
    }
    _startedByPress = false;
    _held = false;
  }

  void _toggle() {
    if (_active) {
      unawaited(_c.stopRecording());
    } else if (_c.canSend) {
      unawaited(_c.startRecording());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final recording = c.recording;
    final waiting = c.busy && !recording;
    final enabled = recording || c.startingRecording || c.canSend;
    final label = c.startingRecording
        ? 'Starting the microphone...'
        : recording
            ? 'Listening... release to send'
            : waiting
                ? 'Turning your voice into text...'
                : 'Hold to talk';
    final color = recording
        ? AppColors.error
        : waiting
            ? AppColors.textMuted
            : !enabled
                ? AppColors.border
                : AppColors.teal;
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor:
          enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          _toggle();
          return null;
        }),
      },
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        onTap: enabled ? _toggle : null,
        excludeSemantics: true,
        child: Listener(
          onPointerDown: _down,
          onPointerUp: _up,
          onPointerCancel: _up,
          child: Container(
            key: const Key('live-talk'),
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(kRadius),
              border: Border.all(
                color: _focused ? AppColors.tealDark : color,
                width: _focused ? 3 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(recording ? Icons.mic : Icons.mic_none,
                    color: Colors.white),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    key: const Key('live-talk-label'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
