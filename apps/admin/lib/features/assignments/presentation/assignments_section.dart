import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../application/participant_assignments_controller.dart';

/// The Assignments section of the participant detail. Researchers assign a
/// published protocol, attach approved content when an interest conversation
/// waits for it, and cancel; analysts only read.
class AssignmentsSection extends StatefulWidget {
  const AssignmentsSection({
    super.key,
    required this.studyId,
    required this.code,
    required this.canEdit,
  });

  final int studyId;
  final String code;
  final bool canEdit;

  @override
  State<AssignmentsSection> createState() => _AssignmentsSectionState();
}

class _AssignmentsSectionState extends State<AssignmentsSection> {
  late final ParticipantAssignmentsController _controller;
  String? _protocolId;
  final _order = TextEditingController();
  final Map<String, String> _contentPick = {};

  @override
  void initState() {
    super.initState();
    final deps = AppScope.read(context);
    _controller = ParticipantAssignmentsController(
      assignments: deps.assignments,
      protocols: deps.protocols,
      content: deps.content,
      studyId: widget.studyId,
      code: widget.code,
    )..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _order.dispose();
    super.dispose();
  }

  Future<void> _assign() async {
    final id = _protocolId;
    if (id == null) return;
    final text = _order.text.trim();
    final order = text.isEmpty ? null : int.tryParse(text);
    if (text.isNotEmpty && order == null) {
      return;
    }
    if (await _controller.assign(id, orderIndex: order)) {
      setState(() {
        _protocolId = null;
        _order.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        return Card(
          key: const Key('assignments-section'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Assignments', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (c.error != null) ...[
                  MessageBanner(
                    key: const Key('assignments-error'),
                    message: c.error!,
                    onDismiss: c.dismissError,
                  ),
                  const SizedBox(height: 8),
                ] else if (c.notice != null) ...[
                  MessageBanner(
                    key: const Key('assignments-notice'),
                    message: c.notice!,
                    kind: BannerKind.success,
                    onDismiss: c.dismissNotice,
                  ),
                  const SizedBox(height: 8),
                ],
                if (c.loading && !c.loadedOnce)
                  const Center(child: CircularProgressIndicator())
                else if (c.items.isEmpty)
                  const Text('Nothing is assigned to this participant yet.',
                      key: Key('no-assignments'))
                else
                  for (var i = 0; i < c.items.length; i++) ...[
                    if (i > 0) const Divider(height: 20),
                    _AssignmentRow(
                      assignment: c.items[i],
                      controller: c,
                      canEdit: widget.canEdit,
                      pick: _contentPick[c.items[i].id],
                      onPick: (v) =>
                          setState(() => _contentPick[c.items[i].id] = v),
                    ),
                  ],
                if (widget.canEdit) ...[
                  const Divider(height: 28),
                  Text('Assign a protocol', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (c.publishedProtocols.isEmpty)
                    Text(
                      'There is no published protocol yet. Publish one in the '
                      'Protocols tab first.',
                      key: const Key('no-published-protocols'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    )
                  else
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 320,
                          child: DropdownButtonFormField<String>(
                            key: const Key('assign-protocol'),
                            initialValue: _protocolId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Published protocol'),
                            items: [
                              for (final p in c.publishedProtocols)
                                DropdownMenuItem(
                                  value: p.id,
                                  child: Text(
                                    '${p.name} · version ${p.version} · '
                                    '${p.path?.label ?? ''}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (v) => setState(() => _protocolId = v),
                          ),
                        ),
                        SizedBox(
                          width: 140,
                          child: TextField(
                            key: const Key('assign-order'),
                            controller: _order,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Order (optional)',
                            ),
                          ),
                        ),
                        FilledButton(
                          key: const Key('assign-submit'),
                          onPressed:
                              _protocolId == null || c.busy ? null : _assign,
                          child: const Text('Assign protocol'),
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AssignmentRow extends StatelessWidget {
  const _AssignmentRow({
    required this.assignment,
    required this.controller,
    required this.canEdit,
    required this.pick,
    required this.onPick,
  });

  final Assignment assignment;
  final ParticipantAssignmentsController controller;
  final bool canEdit;
  final String? pick;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final a = assignment;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final choices = controller.contentFor(a);
    final selected = choices.any((c) => c.item.id == pick) ? pick : null;
    final open = a.status != AssignmentStatus.cancelled &&
        a.status != AssignmentStatus.completed;
    return Column(
      key: Key('assignment-${a.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('${a.orderIndex + 1}.', style: theme.textTheme.titleSmall),
            Text(
              '${a.protocol.name} · version ${a.protocol.version}',
              style: theme.textTheme.titleSmall,
            ),
            Container(
              key: Key('assignment-status-${a.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: a.status == AssignmentStatus.completed
                    ? AppColors.successTint
                    : (a.status == AssignmentStatus.cancelled
                        ? AppColors.background
                        : AppColors.warningTint),
                borderRadius: BorderRadius.circular(kRadius),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(assignmentStatusLabel(a.status),
                  style: theme.textTheme.labelMedium),
            ),
          ],
        ),
        if (a.protocol.path != null)
          Text(a.protocol.path!.label,
              style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        if (a.topic != null)
          Text('Topic: ${a.topic}'
              '${a.topicFreeText == null ? '' : ' · "${a.topicFreeText}"'}',
              key: Key('assignment-topic-${a.id}'),
              style: theme.textTheme.bodyMedium),
        if (a.contentTitle != null)
          Text('Content: ${a.contentTitle}',
              key: Key('assignment-content-${a.id}'),
              style: theme.textTheme.bodyMedium),
        if (canEdit && a.status == AssignmentStatus.contentPending) ...[
          const SizedBox(height: 8),
          if (choices.isEmpty)
            Text(
              'No approved content yet. Approve some in the Content tab.',
              key: Key('no-content-${a.id}'),
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 340,
                  child: DropdownButtonFormField<String>(
                    key: Key('attach-content-${a.id}'),
                    initialValue: selected,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Approved content'),
                    items: [
                      for (final c in choices)
                        DropdownMenuItem(
                          value: c.item.id,
                          child: Text(
                            c.matchesTopic
                                ? '${c.item.title} (matches topic)'
                                : c.item.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => v == null ? null : onPick(v),
                  ),
                ),
                FilledButton(
                  key: Key('attach-submit-${a.id}'),
                  onPressed: selected == null || controller.busy
                      ? null
                      : () => controller.attach(a.id, selected),
                  child: const Text('Attach content'),
                ),
              ],
            ),
        ],
        if (canEdit && open) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: Key('cancel-assignment-${a.id}'),
              onPressed: controller.busy ? null : () => controller.cancel(a.id),
              child: const Text('Cancel assignment'),
            ),
          ),
        ],
      ],
    );
  }
}
