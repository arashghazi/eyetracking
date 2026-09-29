import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../application/demographics_form_controller.dart';

class DemographicsFormTab extends StatefulWidget {
  const DemographicsFormTab({super.key, required this.studyId});

  final int studyId;

  @override
  State<DemographicsFormTab> createState() => _DemographicsFormTabState();
}

class _DemographicsFormTabState extends State<DemographicsFormTab>
    with AutomaticKeepAliveClientMixin {
  late final DemographicsFormController _controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = DemographicsFormController(
      AppScope.read(context).demographicsForm,
      widget.studyId,
    );
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmAndPublish() async {
    if (!_controller.validate()) {
      // Shows the row errors and the banner without calling the server.
      await _controller.publish();
      return;
    }
    final current = _controller.current;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish a new version?'),
        content: Text(
          current == null
              ? 'This publishes the first version of the demographics form.'
              : 'This publishes version ${current.version + 1}. Participants '
                  'may need to update their answers.',
        ),
        actions: [
          TextButton(
            key: const Key('form-publish-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('form-publish-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _controller.publish();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        return PageFrame(
          maxWidth: 900,
          banner: c.error != null
              ? MessageBanner(message: c.error!, onDismiss: c.dismissError)
              : c.notice != null
                  ? MessageBanner(
                      message: c.notice!,
                      kind: BannerKind.success,
                      onDismiss: c.dismissNotice,
                    )
                  : null,
          children: [
            Text('Demographics form', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            if (c.loading && !c.loaded)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!c.loaded)
              OutlinedButton(onPressed: c.load, child: const Text('Try again'))
            else ...[
              Text(
                c.current == null
                    ? 'No demographics form has been published for this study yet.'
                    : 'Current version: ${c.current!.version}.',
                key: const Key('form-version'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < c.rows.length; i++) ...[
                _FieldEditor(
                  key: ValueKey('row-${c.rows[i].id}'),
                  controller: c,
                  row: c.rows[i],
                  position: i,
                  isFirst: i == 0,
                  isLast: i == c.rows.length - 1,
                ),
                const SizedBox(height: 12),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('add-field'),
                    onPressed: c.addRow,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add field'),
                  ),
                  FilledButton(
                    key: const Key('publish-form'),
                    onPressed: c.publishing ? null : _confirmAndPublish,
                    child: Text(
                      c.publishing ? 'Publishing...' : 'Publish new version',
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _FieldEditor extends StatelessWidget {
  const _FieldEditor({
    super.key,
    required this.controller,
    required this.row,
    required this.position,
    required this.isFirst,
    required this.isLast,
  });

  final DemographicsFormController controller;
  final FieldDraft row;
  final int position;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = controller.errorFor(row);
    final id = row.id;

    final keyField = TextFormField(
      key: ValueKey('key-$id'),
      initialValue: row.key,
      decoration: const InputDecoration(
        labelText: 'Key',
        helperText: 'Stored with each answer',
      ),
      onChanged: (v) => controller.update(row, key: v),
    );
    final labelField = TextFormField(
      key: ValueKey('label-$id'),
      initialValue: row.label,
      decoration: const InputDecoration(
        labelText: 'Label',
        helperText: 'Shown to the participant',
      ),
      onChanged: (v) => controller.update(row, label: v),
    );
    final typeField = DropdownButtonFormField<DemographicsFieldType>(
      key: ValueKey('type-$id'),
      initialValue: row.type,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Type'),
      items: [
        for (final t in DemographicsFieldType.values)
          DropdownMenuItem(value: t, child: Text(t.label)),
      ],
      onChanged: (v) {
        if (v != null) controller.update(row, type: v);
      },
    );
    final optionsField = TextFormField(
      key: ValueKey('options-$id'),
      initialValue: row.optionsText,
      decoration: const InputDecoration(
        labelText: 'Options',
        helperText: 'Separate with commas',
      ),
      onChanged: (v) => controller.update(row, optionsText: v),
    );

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadius),
        side: BorderSide(color: error == null ? AppColors.border : AppColors.error),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Field ${position + 1}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Move up',
                  onPressed: isFirst ? null : () => controller.moveRow(row, -1),
                  icon: const Icon(Icons.arrow_upward, size: 18),
                ),
                IconButton(
                  tooltip: 'Move down',
                  onPressed: isLast ? null : () => controller.moveRow(row, 1),
                  icon: const Icon(Icons.arrow_downward, size: 18),
                ),
                IconButton(
                  key: ValueKey('remove-$id'),
                  tooltip: 'Remove field',
                  onPressed: () => controller.removeRow(row),
                  icon: const Icon(Icons.delete_outline, size: 18),
                ),
              ],
            ),
            LayoutBuilder(builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 560;
              final width = twoColumns
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final w in [
                    keyField,
                    labelField,
                    typeField,
                    if (row.type == DemographicsFieldType.choice) optionsField,
                  ])
                    SizedBox(width: width, child: w),
                ],
              );
            }),
            SwitchListTile(
              key: ValueKey('required-$id'),
              value: row.required,
              onChanged: (v) => controller.update(row, required: v),
              contentPadding: EdgeInsets.zero,
              title: const Text('Required'),
            ),
            if (error != null)
              Text(
                error,
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.error),
              ),
          ],
        ),
      ),
    );
  }
}
