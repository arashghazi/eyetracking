import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../application/content_controller.dart';
import 'content_editor_screen.dart';

/// The Content tab: interest-path conversations authored for one study, with
/// their status and any media that is still missing.
class ContentTab extends StatefulWidget {
  const ContentTab({super.key, required this.studyId, required this.canEdit});

  final int studyId;
  final bool canEdit;

  @override
  State<ContentTab> createState() => _ContentTabState();
}

class _ContentTabState extends State<ContentTab>
    with AutomaticKeepAliveClientMixin {
  late final ContentController _controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = ContentController(
      AppScope.read(context).content,
      widget.studyId,
    )..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open({String? contentId}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ContentEditorScreen(
          studyId: widget.studyId,
          canEdit: widget.canEdit,
          contentId: contentId,
        ),
      ),
    );
    if (mounted) await _controller.load();
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
                Text('Content', style: theme.textTheme.titleLarge),
                if (c.loadedOnce)
                  Text(
                    '${c.items.length} in total',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                OutlinedButton.icon(
                  key: const Key('reload-content'),
                  onPressed: c.loading ? null : c.load,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reload'),
                ),
                if (widget.canEdit)
                  FilledButton.icon(
                    key: const Key('new-content'),
                    onPressed: () => _open(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New content'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Conversations for the interest path. A draft needs every video '
              'uploaded before it can be approved and attached to a participant.',
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
              const Text('No content yet. Create some with New content.',
                  key: Key('no-content'))
            else
              Container(
                key: const Key('content-table'),
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
                    dataRowMaxHeight: 60,
                    columns: const [
                      DataColumn(label: Text('Title')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Topic tags')),
                      DataColumn(label: Text('Face')),
                      DataColumn(label: Text('Voice')),
                      DataColumn(label: Text('Media')),
                      DataColumn(label: Text('')),
                    ],
                    rows: [
                      for (final item in c.items)
                        DataRow(cells: [
                          DataCell(Text(item.title)),
                          DataCell(_Status(approved: item.isApproved)),
                          DataCell(Text(item.topicTags.isEmpty
                              ? '-'
                              : item.topicTags.join(', '))),
                          DataCell(Text(item.faceId.isEmpty ? '-' : item.faceId)),
                          DataCell(Text(item.voiceId.isEmpty ? '-' : item.voiceId)),
                          DataCell(_MediaCell(item: item)),
                          DataCell(TextButton(
                            key: Key('open-content-${item.id}'),
                            onPressed: () => _open(contentId: item.id),
                            child: Text(
                                item.isDraft && widget.canEdit ? 'Edit' : 'View'),
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

class _Status extends StatelessWidget {
  const _Status({required this.approved});

  final bool approved;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: approved ? AppColors.successTint : AppColors.warningTint,
          borderRadius: BorderRadius.circular(kRadius),
        ),
        child: Text(approved ? 'Approved' : 'Draft',
            style: Theme.of(context).textTheme.labelMedium),
      );
}

class _MediaCell extends StatelessWidget {
  const _MediaCell({required this.item});

  final ContentSummary item;

  @override
  Widget build(BuildContext context) {
    if (item.missingMedia.isEmpty) {
      return Text(
        item.mediaKeys.isEmpty ? 'No media' : 'All uploaded',
        key: Key('media-${item.id}'),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Text(
        'Missing: ${item.missingMedia.join(', ')}',
        key: Key('media-${item.id}'),
        style: const TextStyle(color: AppColors.warning),
      ),
    );
  }
}
