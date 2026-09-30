import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../application/ai_controller.dart';
import 'ai_widgets.dart';

/// Providers, worker and the cost cap of the study. Administrators can change
/// the cap; everybody else only reads it.
class AiStatusCard extends StatefulWidget {
  const AiStatusCard({
    super.key,
    required this.controller,
    required this.isAdmin,
  });

  final AiController controller;
  final bool isAdmin;

  @override
  State<AiStatusCard> createState() => _AiStatusCardState();
}

class _AiStatusCardState extends State<AiStatusCard> {
  final _cap = TextEditingController();
  bool _editing = false;

  @override
  void dispose() {
    _cap.dispose();
    super.dispose();
  }

  /// [budget] is null when the status could not be read: the field starts
  /// empty.
  void _startEdit(AiBudget? budget) {
    widget.controller.clearBudgetError();
    _cap.text = budget == null ? '' : formatUnits(budget.costCapUnits);
    setState(() => _editing = true);
  }

  Future<void> _save() async {
    if (await widget.controller.setBudgetCap(_cap.text) && mounted) {
      setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final s = c.status;
        return Card(
          key: const Key('ai-status-card'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Providers and budget', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                const MutedText(
                  'Provider keys live on the server; this app never sees '
                  'them. The cap is an estimate in USD units, not a bill.',
                ),
                const SizedBox(height: 12),
                if (s == null) ...[
                  Text(
                    c.loading
                        ? 'Loading the status...'
                        : 'The status could not be loaded.',
                    key: const Key('ai-status-missing'),
                  ),
                  // Administrators set the cap without being study members,
                  // and the status needs membership.
                  if (widget.isAdmin && !c.loading) ...[
                    if (c.savedBudget != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Cost cap saved: '
                        '${formatUnits(c.savedBudget!.costCapUnits)} units.',
                        key: const Key('cap-saved'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (!_editing) _editButton(c, null),
                      ],
                    ),
                    ..._capEditor(c),
                  ],
                ] else ...[
                  _ProviderRow(
                    keyPrefix: 'text-provider',
                    label: 'Text provider',
                    provider: s.textProvider,
                  ),
                  const Divider(height: 20),
                  _ProviderRow(
                    keyPrefix: 'video-provider',
                    label: 'Video provider',
                    provider: s.videoProvider,
                  ),
                  const Divider(height: 20),
                  _LabelRow(
                    label: 'Worker',
                    children: [
                      Text(
                        s.worker.enabled
                            ? 'On, runs queued jobs every ${s.worker.intervalS} s'
                            : 'Off, use "Run queued jobs now"',
                        key: const Key('worker-state'),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  _LabelRow(
                    label: 'Budget',
                    children: [
                      _Figure(
                        keyName: 'budget-cap',
                        label: 'Cap',
                        value: formatUnits(s.budget.costCapUnits),
                      ),
                      _Figure(
                        keyName: 'budget-spent',
                        label: 'Spent',
                        value: formatUnits(s.budget.spentUnits),
                      ),
                      _Figure(
                        keyName: 'budget-remaining',
                        label: 'Remaining',
                        value: formatUnits(s.budget.remainingUnits),
                      ),
                      if (widget.isAdmin && !_editing) _editButton(c, s.budget),
                    ],
                  ),
                  if (s.budget.costCapUnits <= 0) ...[
                    const SizedBox(height: 8),
                    const MutedText(
                      'The cap is 0, so nothing runs on a paid provider until '
                      'an administrator sets one.',
                    ),
                  ],
                  ..._capEditor(c),
                  const Divider(height: 20),
                  _LabelRow(
                    label: 'Free text',
                    children: [
                      if (widget.isAdmin)
                        Switch(
                          key: const Key('send-free-text'),
                          value: s.sendFreeText,
                          onChanged: c.busy ? null : c.setSendFreeText,
                        )
                      else
                        Text(
                          s.sendFreeText ? 'On' : 'Off',
                          key: const Key('send-free-text-state'),
                        ),
                      Text(s.sendFreeText ? 'Send free text' : 'Do not send'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const MutedText(
                    "A participant's free-text topic is sent to the text "
                    'provider only when this is on.',
                  ),
                ],
                if (c.budgetError != null) ...[
                  const SizedBox(height: 8),
                  MessageBanner(
                    key: const Key('budget-error'),
                    message: c.budgetError!,
                    onDismiss: c.clearBudgetError,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _editButton(AiController c, AiBudget? budget) => OutlinedButton.icon(
        key: const Key('edit-cap'),
        onPressed: c.busy ? null : () => _startEdit(budget),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('Edit cap'),
      );

  /// The cap field with Save and Cancel, while an administrator edits.
  List<Widget> _capEditor(AiController c) => [
        if (widget.isAdmin && _editing) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              SizedBox(
                width: 200,
                child: TextField(
                  key: const Key('cap-field'),
                  controller: _cap,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'New cap (USD units)',
                  ),
                  onSubmitted: (_) => _save(),
                ),
              ),
              FilledButton(
                key: const Key('save-cap'),
                onPressed: c.busy ? null : _save,
                child: const Text('Save cap'),
              ),
              OutlinedButton(
                key: const Key('cancel-cap'),
                onPressed: () {
                  c.clearBudgetError();
                  setState(() => _editing = false);
                },
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ];
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.keyPrefix,
    required this.label,
    required this.provider,
  });

  final String keyPrefix;
  final String label;
  final AiProviderStatus provider;

  @override
  Widget build(BuildContext context) {
    final model = provider.model;
    final name = provider.name.isEmpty ? 'unknown' : provider.name;
    return KeyedSubtree(
      key: Key(keyPrefix),
      child: _LabelRow(
        label: label,
        children: [
          Text(
            model == null ? name : '$name, $model',
            key: Key('$keyPrefix-name'),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: kMonospaceFallback,
            ),
          ),
          KeyedSubtree(
            key: Key('$keyPrefix-state'),
            child: ConfiguredChip(configured: provider.configured),
          ),
          if (provider.synthetic)
            KeyedSubtree(
              key: Key('$keyPrefix-synthetic'),
              child: const SyntheticBadge(),
            ),
        ],
      ),
    );
  }
}

class _LabelRow extends StatelessWidget {
  const _LabelRow({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          ...children,
        ],
      );
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.keyName,
    required this.label,
    required this.value,
  });

  final String keyName;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Text.rich(
        key: Key(keyName),
        TextSpan(children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ]),
      );
}
