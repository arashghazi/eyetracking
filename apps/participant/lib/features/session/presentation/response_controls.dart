import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/practice_trials.dart';
import 'symbol_glyph.dart';

/// The controls that answer one trial: typed number (Enter submits), an
/// on-screen digit pad on touch screens, four number buttons, or four
/// picture symbols. Rebuilt for every trial (give it a fresh key).
class ResponseControls extends StatelessWidget {
  const ResponseControls({
    super.key,
    required this.input,
    required this.options,
    required this.touch,
    required this.onSubmit,
  });

  final TrialInput input;

  /// The four choices of [TrialInput.fourChoice] and [TrialInput.symbol].
  final List<String> options;

  /// Show the on-screen digit pad instead of the keyboard field.
  final bool touch;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) => switch (input) {
        TrialInput.number =>
          touch ? DigitPad(onSubmit: onSubmit) : NumberField(onSubmit: onSubmit),
        TrialInput.fourChoice => _Choices(
            options: options,
            onPick: onSubmit,
            builder: (o) => Text(o,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
          ),
        TrialInput.symbol => _Choices(
            options: options,
            onPick: onSubmit,
            builder: (o) => SymbolGlyph(name: o, size: 32),
          ),
      };
}

/// A text field for one or two digits; Enter submits.
class NumberField extends StatefulWidget {
  const NumberField({super.key, required this.onSubmit});

  final ValueChanged<String> onSubmit;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) widget.onSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 140,
          child: TextField(
            key: const Key('answer-field'),
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 2,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              hintText: 'Number',
              counterText: '',
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          key: const Key('answer-submit'),
          onPressed: _submit,
          child: const Text('Answer'),
        ),
      ],
    );
  }
}

/// Ten digit keys in two rows, a display, backspace and Answer.
class DigitPad extends StatefulWidget {
  const DigitPad({super.key, required this.onSubmit});

  final ValueChanged<String> onSubmit;

  @override
  State<DigitPad> createState() => _DigitPadState();
}

class _DigitPadState extends State<DigitPad> {
  String _value = '';

  void _press(String digit) {
    if (_value.length >= 2) return;
    setState(() => _value += digit);
  }

  void _back() {
    if (_value.isEmpty) return;
    setState(() => _value = _value.substring(0, _value.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    Widget key(String d) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: OutlinedButton(
              key: Key('pad-$d'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: EdgeInsets.zero,
                textStyle:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              onPressed: () => _press(d),
              child: Text(d),
            ),
          ),
        );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [for (final d in ['1', '2', '3', '4', '5']) key(d)]),
            Row(children: [for (final d in ['6', '7', '8', '9', '0']) key(d)]),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(kRadius),
                      ),
                      child: Text(
                        _value.isEmpty ? ' ' : _value,
                        key: const Key('pad-display'),
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: OutlinedButton(
                        key: const Key('pad-back'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: _back,
                        child: const Icon(Icons.backspace_outlined, size: 20),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: FilledButton(
                        key: const Key('answer-submit'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed:
                            _value.isEmpty ? null : () => widget.onSubmit(_value),
                        child: const Text('Answer'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Choices extends StatelessWidget {
  const _Choices({
    required this.options,
    required this.onPick,
    required this.builder,
  });

  final List<String> options;
  final ValueChanged<String> onPick;
  final Widget Function(String option) builder;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Row(
          children: [
            for (final o in options)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: SizedBox(
                    height: 64,
                    child: OutlinedButton(
                      key: Key('choice-$o'),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 56),
                      ),
                      onPressed: () => onPick(o),
                      child: builder(o),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
