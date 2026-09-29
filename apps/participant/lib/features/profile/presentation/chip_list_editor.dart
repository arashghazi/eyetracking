import 'package:flutter/material.dart';

/// Chips with a free-text "add" field. Pressing Enter adds the entry.
class ChipListEditor extends StatefulWidget {
  const ChipListEditor({
    super.key,
    required this.label,
    required this.hint,
    required this.values,
    required this.onAdd,
    required this.onRemove,
  });

  final String label;
  final String hint;
  final List<String> values;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  @override
  State<ChipListEditor> createState() => _ChipListEditorState();
}

class _ChipListEditorState extends State<ChipListEditor> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _add() {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    widget.onAdd(value);
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (widget.values.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final v in widget.values)
                  InputChip(
                    label: Text(v),
                    onDeleted: () => widget.onRemove(v),
                    deleteButtonTooltipMessage: 'Remove $v',
                  ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                decoration: InputDecoration(hintText: widget.hint),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _add, child: const Text('Add')),
          ],
        ),
      ],
    );
  }
}
