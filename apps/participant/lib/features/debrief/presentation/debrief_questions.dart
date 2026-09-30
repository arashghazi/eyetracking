import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/debrief_models.dart';

/// One question of the debrief on its own row: the prompt (with a Required
/// mark) and the input that fits its type. [value] is the current answer;
/// [onChanged] gets the new one, or null when it is cleared.
class DebriefQuestionRow extends StatelessWidget {
  const DebriefQuestionRow({
    super.key,
    required this.question,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final ParticipantDebriefQuestion question;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final q = question;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                q.prompt,
                key: Key('debrief-${q.key}-prompt'),
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (q.required) ...[
              const SizedBox(width: 8),
              Text(
                'Required',
                key: Key('debrief-${q.key}-required'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        switch (q.type) {
          ParticipantDebriefQuestionType.scale => _ScaleInput(
            question: q,
            value: value,
            enabled: enabled,
            onChanged: onChanged,
          ),
          ParticipantDebriefQuestionType.yesNo => _Chips(
            enabled: enabled,
            options: [
              (key: Key('debrief-${q.key}-yes'), label: 'Yes', value: true),
              (key: Key('debrief-${q.key}-no'), label: 'No', value: false),
            ],
            value: value,
            onChanged: onChanged,
          ),
          ParticipantDebriefQuestionType.choice => _Chips(
            enabled: enabled,
            options: [
              for (var i = 0; i < q.options.length; i++)
                (
                  key: Key('debrief-${q.key}-option-$i'),
                  label: q.options[i],
                  value: q.options[i],
                ),
            ],
            value: value,
            onChanged: onChanged,
          ),
          ParticipantDebriefQuestionType.text => _TextInput(
            question: q,
            value: value,
            enabled: enabled,
            onChanged: onChanged,
          ),
        },
      ],
    );
  }
}

typedef _Option = ({Key key, String label, Object value});

/// Yes/no and choice: one chip per option; tapping the chosen one again
/// clears the answer.
class _Chips extends StatelessWidget {
  const _Chips({
    required this.options,
    required this.value,
    required this.onChanged,
    required this.enabled,
  });

  final List<_Option> options;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in options)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth),
              child: ChoiceChip(
                key: o.key,
                label: Text(o.label),
                selected: value == o.value,
                showCheckmark: false,
                onSelected: enabled
                    ? (on) => onChanged(on ? o.value : null)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// A row of numbered chips with the first and last label under the ends and
/// the chosen label below. On a narrow screen with many points the chips
/// wrap to a second line instead of shrinking below a tappable size.
class _ScaleInput extends StatelessWidget {
  const _ScaleInput({
    required this.question,
    required this.value,
    required this.onChanged,
    required this.enabled,
  });

  final ParticipantDebriefQuestion question;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final bool enabled;

  static const _gap = 6.0;
  static const _minChip = 36.0;
  static const _maxChip = 64.0;
  static const _wrappedChip = 44.0;

  @override
  Widget build(BuildContext context) {
    final q = question;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final n = q.scaleMax;
    final first = q.labelFor(1);
    final last = q.labelFor(n);
    final chosen = value is int ? q.labelFor(value as int) : null;

    return LayoutBuilder(
      builder: (context, box) {
        final fit = (box.maxWidth - _gap * (n - 1)) / n;
        final single = fit >= _minChip;
        final chipWidth = single ? math.min(fit, _maxChip) : _wrappedChip;
        final rowWidth = single ? chipWidth * n + _gap * (n - 1) : box.maxWidth;
        final chips = [
          for (var v = 1; v <= n; v++)
            SizedBox(
              width: chipWidth,
              height: 40,
              child: ChoiceChip(
                key: Key('debrief-${q.key}-$v'),
                label: SizedBox(
                  width: double.infinity,
                  child: Text('$v', textAlign: TextAlign.center),
                ),
                tooltip: q.labelFor(v),
                selected: value == v,
                showCheckmark: false,
                padding: EdgeInsets.zero,
                labelPadding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: enabled ? (on) => onChanged(on ? v : null) : null,
              ),
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: rowWidth,
              child: single
                  ? Row(
                      children: [
                        for (var i = 0; i < chips.length; i++) ...[
                          if (i > 0) const SizedBox(width: _gap),
                          chips[i],
                        ],
                      ],
                    )
                  : Wrap(spacing: _gap, runSpacing: _gap, children: chips),
            ),
            if (first != null || last != null) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: rowWidth,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        first ?? '',
                        key: Key('debrief-${q.key}-first-label'),
                        style: muted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        last ?? '',
                        key: Key('debrief-${q.key}-last-label'),
                        textAlign: TextAlign.end,
                        style: muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (chosen != null) ...[
              const SizedBox(height: 4),
              Text(
                'Chosen: $chosen',
                key: Key('debrief-${q.key}-chosen'),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A multi-line field. Enter adds a new line; nothing is submitted from
/// here. The counter shows the limit.
class _TextInput extends StatefulWidget {
  const _TextInput({
    required this.question,
    required this.value,
    required this.onChanged,
    required this.enabled,
  });

  final ParticipantDebriefQuestion question;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final bool enabled;

  @override
  State<_TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<_TextInput> {
  late final TextEditingController _text = TextEditingController(
    text: widget.value is String ? widget.value as String : '',
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.question.prompt,
      child: TextField(
        key: Key('debrief-${widget.question.key}-text'),
        controller: _text,
        enabled: widget.enabled,
        minLines: 3,
        maxLines: 6,
        maxLength: debriefTextMaxLength,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (text) => widget.onChanged(text),
      ),
    );
  }
}
