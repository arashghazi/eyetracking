import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../application/erase_controller.dart';

/// "Withdraw and delete my data": a plain explanation and a button that
/// opens a dialog asking for the phrase `DELETE MY DATA`.
class EraseSection extends StatefulWidget {
  const EraseSection({super.key});

  @override
  State<EraseSection> createState() => _EraseSectionState();
}

class _EraseSectionState extends State<EraseSection> {
  late final EraseController _controller;

  @override
  void initState() {
    super.initState();
    final deps = AppScope.read(context);
    _controller = EraseController(
      deps.erase,
      onErased: (result) =>
          deps.auth.signOutWithNotice(EraseController.farewell(result)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final typed = await EraseDialog.show(context);
    if (typed != null) await _controller.erase(typed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        return Card(
          key: const Key('erase-section'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Withdraw and delete my data',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'You can leave the study at any time, without giving a reason.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'What happens: your consent, your profile, your answers about '
                  'yourself, your sessions and the gaze numbers and events '
                  'recorded in them are deleted, and your account is closed. '
                  'Your email address is removed, so you cannot sign in again. '
                  'This cannot be undone. Before you go, you can download your '
                  'data from "Download my data".',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (c.error != null) ...[
                  MessageBanner(message: c.error!, onDismiss: c.dismissError),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  key: const Key('erase-open'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                  onPressed: c.busy ? null : _open,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(
                    c.busy ? 'Deleting...' : 'Withdraw and delete my data',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Asks for the phrase; returns what was typed when the person confirmed,
/// or null when they cancelled.
class EraseDialog extends StatefulWidget {
  const EraseDialog({super.key});

  static Future<String?> show(BuildContext context) =>
      showDialog<String>(context: context, builder: (_) => const EraseDialog());

  @override
  State<EraseDialog> createState() => _EraseDialogState();
}

class _EraseDialogState extends State<EraseDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _matches => EraseController.matches(_typed.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete your data and close your account?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your data will be deleted and your account closed. You will be '
                'signed out and cannot sign in again. This cannot be undone.',
              ),
              const SizedBox(height: 12),
              const Text('To confirm, type ${EraseController.phrase} below.'),
              const SizedBox(height: 8),
              TextField(
                key: const Key('erase-phrase'),
                controller: _typed,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmation',
                  hintText: EraseController.phrase,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (_matches) Navigator.of(context).pop(_typed.text);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('erase-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Keep my data'),
        ),
        FilledButton(
          key: const Key('erase-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
          onPressed: _matches
              ? () => Navigator.of(context).pop(_typed.text)
              : null,
          child: const Text('Delete my data'),
        ),
      ],
    );
  }
}
