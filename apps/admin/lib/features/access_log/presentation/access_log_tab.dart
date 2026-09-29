import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../application/access_log_controller.dart';

/// Every export, replay, analysis view, identity reveal and deletion of the
/// study, newest first. Researchers and administrators see it.
class AccessLogTab extends StatefulWidget {
  const AccessLogTab({super.key, required this.studyId});

  final int studyId;

  @override
  State<AccessLogTab> createState() => _AccessLogTabState();
}

class _AccessLogTabState extends State<AccessLogTab>
    with AutomaticKeepAliveClientMixin {
  late final AccessLogController _controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = AccessLogController(
      AppScope.read(context).accessLog,
      widget.studyId,
    )..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
                Text('Access log', style: theme.textTheme.titleLarge),
                if (c.loadedOnce)
                  Text(
                    'Latest ${c.entries.length}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                OutlinedButton.icon(
                  key: const Key('reload-access-log'),
                  onPressed: c.loading ? null : c.load,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reload'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Exports, replays, analysis views, identity reveals and '
              'deletions of this study are recorded here.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (c.loading && !c.loadedOnce)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (c.entries.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    c.loadedOnce
                        ? 'Nothing has been recorded yet.'
                        : 'The access log could not be loaded.',
                  ),
                ),
              )
            else
              AccessLogTable(entries: c.entries),
          ],
        );
      },
    );
  }
}

class AccessLogTable extends StatelessWidget {
  const AccessLogTable({super.key, required this.entries});

  final List<AccessLogEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              key: const Key('access-log-table'),
              columnSpacing: 24,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 64,
              columns: const [
                DataColumn(label: Text('At')),
                DataColumn(label: Text('Role')),
                DataColumn(label: Text('Action')),
                DataColumn(label: Text('Detail')),
              ],
              rows: [
                for (final e in entries)
                  DataRow(cells: [
                    DataCell(Text(formatTimestamp(e.at))),
                    DataCell(Text(e.role.isEmpty ? '—' : e.role)),
                    DataCell(Text(
                      e.action,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontFamilyFallback: kMonospaceFallback,
                      ),
                    )),
                    DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Text(
                        e.detail.isEmpty ? '—' : e.detail,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
                  ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
