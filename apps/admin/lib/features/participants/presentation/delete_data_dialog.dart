import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

/// Asks the researcher to type the research code before a participant's
/// research data is deleted. Returns true when confirmed.
class DeleteDataDialog extends StatefulWidget {
  const DeleteDataDialog({super.key, required this.code});

  final String code;

  static Future<bool> show(BuildContext context, String code) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => DeleteDataDialog(code: code),
      ) ??
      false;

  @override
  State<DeleteDataDialog> createState() => _DeleteDataDialogState();
}

class _DeleteDataDialogState extends State<DeleteDataDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _matches => _typed.text.trim() == widget.code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text("Delete this participant's research data?"),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This deletes every session, gaze sample, event, trial and '
                'answer of ${widget.code}, and their consents, demographics, '
                'profile and assignments. It cannot be undone. The account and '
                'the research code stay, so the person can still sign in and '
                'will see an empty record.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'To confirm, type the research code ${widget.code}.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('delete-code-field'),
                controller: _typed,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Research code',
                  hintText: widget.code,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (_matches) Navigator.of(context).pop(true);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('delete-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('delete-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Delete research data'),
        ),
      ],
    );
  }
}
