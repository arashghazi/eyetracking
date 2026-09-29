import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../application/protocols_controller.dart';
import 'protocol_editor_screen.dart';

/// The Protocols tab: the practice protocols of one study. Researchers
/// create drafts, publish them and copy a published version into a new
/// draft; analysts only look.
class ProtocolsTab extends StatefulWidget {
  const ProtocolsTab({super.key, required this.studyId, required this.canEdit});

  final int studyId;
  final bool canEdit;

  @override
  State<ProtocolsTab> createState() => _ProtocolsTabState();
}

class _ProtocolsTabState extends State<ProtocolsTab>
    with AutomaticKeepAliveClientMixin {
  late final ProtocolsController _controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = ProtocolsController(
      AppScope.read(context).protocols,
      widget.studyId,
    )..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open({String? protocolId, ProtocolDetail? initial}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProtocolEditorScreen(
          studyId: widget.studyId,
          canEdit: widget.canEdit,
          protocolId: protocolId,
          initial: initial,
        ),
      ),
    );
    if (mounted) await _controller.load();
  }

  Future<void> _newDraftFrom(ProtocolSummary p) async {
    final draft = await _controller.newDraftFrom(p);
    if (draft != null && mounted) await _open(initial: draft);
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
          maxWidth: 1200,
          banner: c.error != null
              ? MessageBanner(message: c.error!, onDismiss: c.dismissError)
              : null,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Protocols', style: theme.textTheme.titleLarge),
                if (c.loadedOnce)
                  Text(
                    '${c.items.length} in total',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                OutlinedButton.icon(
                  key: const Key('reload-protocols'),
                  onPressed: c.loading ? null : c.load,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reload'),
                ),
                if (widget.canEdit)
                  FilledButton.icon(
                    key: const Key('new-protocol'),
                    onPressed: () => _open(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New protocol'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'A protocol says how one practice session runs. Published '
              'versions never change; edit a copy instead.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (c.loading && !c.loadedOnce)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!c.loadedOnce)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                    onPressed: c.load, child: const Text('Try again')),
              )
            else if (c.items.isEmpty)
              const Text(
                'No protocols yet. Create one with New protocol.',
                key: Key('no-protocols'),
              )
            else
              Container(
                key: const Key('protocols-table'),
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(kRadius),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 20,
                    dataRowMinHeight: 44,
                    dataRowMaxHeight: 52,
                    columns: const [
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Version'), numeric: true),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Path')),
                      DataColumn(label: Text('Created')),
                      DataColumn(label: Text('Published')),
                      DataColumn(label: Text('')),
                    ],
                    rows: [
                      for (final p in c.items)
                        DataRow(cells: [
                          DataCell(Text(p.name)),
                          DataCell(Text(p.version == 0 ? '-' : '${p.version}')),
                          DataCell(_StatusChip(published: p.isPublished)),
                          DataCell(Text(p.path?.label ?? '-')),
                          DataCell(Text(formatTimestamp(p.createdAt))),
                          DataCell(Text(formatTimestamp(p.publishedAt))),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                key: Key('open-protocol-${p.id}'),
                                onPressed: () => _open(protocolId: p.id),
                                child: Text(
                                    p.isDraft && widget.canEdit ? 'Edit' : 'View'),
                              ),
                              if (p.isPublished && widget.canEdit)
                                TextButton(
                                  key: Key('new-draft-${p.id}'),
                                  onPressed:
                                      c.busy ? null : () => _newDraftFrom(p),
                                  child: const Text('New draft'),
                                ),
                            ],
                          )),
                        ]),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.published});

  final bool published;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: published ? AppColors.successTint : AppColors.warningTint,
          borderRadius: BorderRadius.circular(kRadius),
        ),
        child: Text(
          published ? 'Published' : 'Draft',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      );
}
