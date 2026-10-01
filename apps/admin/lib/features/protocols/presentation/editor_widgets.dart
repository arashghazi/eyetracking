import 'package:flutter/material.dart';

// Building blocks of the protocol editor: a card with a title, a text box
// that starts over when its revision changes, a dropdown and a switch.

class EditorSection extends StatelessWidget {
  const EditorSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );
}

/// A text box that starts from [value] and starts over when [revision] changes.
class EditorText extends StatelessWidget {
  const EditorText({
    super.key,
    required this.keyName,
    required this.label,
    required this.revision,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.width,
    this.number = false,
    this.minLines,
    this.maxLines = 1,
    this.errorText,
    this.helperText,
    this.counterText,
    this.invalid = false,
  });

  final String keyName;
  final String label;
  final int revision;
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final double? width;
  final bool number;

  /// More than one line makes it a multi-line box.
  final int? minLines;
  final int? maxLines;
  final String? errorText;
  final String? helperText;
  final String? counterText;

  /// Marks the box as wrong without a message of its own (the message is
  /// shown elsewhere).
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    final field = KeyedSubtree(
      key: ValueKey('$keyName-$revision'),
      child: TextFormField(
        key: Key(keyName),
        initialValue: value,
        enabled: enabled,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : (maxLines == 1 ? TextInputType.text : TextInputType.multiline),
        minLines: minLines,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          error: errorText == null && invalid ? const SizedBox.shrink() : null,
          errorMaxLines: 3,
          helperText: helperText,
          helperMaxLines: 3,
          counterText: counterText,
        ),
        onChanged: onChanged,
      ),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }
}

class EditorDrop<T> extends StatelessWidget {
  const EditorDrop({
    super.key,
    required this.keyName,
    required this.label,
    required this.revision,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
    this.width,
  });

  final String keyName;
  final String label;
  final int revision;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final bool enabled;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final field = KeyedSubtree(
      key: ValueKey('$keyName-$revision'),
      child: DropdownButtonFormField<T>(
        key: Key(keyName),
        initialValue: items.containsKey(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final e in items.entries)
            DropdownMenuItem<T>(value: e.key, child: Text(e.value)),
        ],
        onChanged: enabled ? (v) => v == null ? null : onChanged(v) : null,
      ),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }
}

class EditorSwitch extends StatelessWidget {
  const EditorSwitch({
    super.key,
    required this.keyName,
    required this.title,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String keyName;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        key: Key(keyName),
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        value: value,
        onChanged: enabled ? onChanged : null,
      );
}
