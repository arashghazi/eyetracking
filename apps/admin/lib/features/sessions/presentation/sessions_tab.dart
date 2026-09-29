import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../application/sessions_controller.dart';
import 'session_detail_screen.dart';
import 'session_widgets.dart';

class SessionsTab extends StatefulWidget {
  const SessionsTab({super.key, required this.studyId});

  final int studyId;

  @override
  State<SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends State<SessionsTab>
    with AutomaticKeepAliveClientMixin {
  late final SessionsController _controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = SessionsController(
      AppScope.read(context).sessions,
      widget.studyId,
    )..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open(SessionListItem item) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SessionDetailScreen(
          studyId: widget.studyId,
          sessionId: item.id,
          participantCode: item.participantCode,
        ),
      ),
    );
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
                Text('Sessions', style: theme.textTheme.titleLarge),
                if (c.loadedOnce)
                  Text(
                    '${c.items.length} in total',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                OutlinedButton.icon(
                  key: const Key('reload-sessions'),
                  onPressed: c.loading ? null : c.load,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reload'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (c.loading && !c.loadedOnce)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (c.items.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    c.loadedOnce
                        ? 'No sessions yet. They appear here after a participant '
                            'starts one in the Participant App.'
                        : 'Sessions could not be loaded.',
                  ),
                ),
              )
            else ...[
              Text(
                'Select a row to see the session in detail.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              _SessionsTable(items: c.items, onOpen: _open),
            ],
          ],
        );
      },
    );
  }
}

class _SessionsTable extends StatelessWidget {
  const _SessionsTable({required this.items, required this.onOpen});

  final List<SessionListItem> items;
  final ValueChanged<SessionListItem> onOpen;

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
              key: const Key('sessions-table'),
              showCheckboxColumn: false,
              columnSpacing: 20,
              dataRowMinHeight: 44,
              dataRowMaxHeight: 56,
              columns: const [
                DataColumn(label: Text('Participant')),
                DataColumn(label: Text('Created')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Quality')),
                DataColumn(label: Text('Estimator')),
                DataColumn(label: Text('Calibration'), numeric: true),
                DataColumn(label: Text('Validation')),
                DataColumn(label: Text('Classifiable'), numeric: true),
                DataColumn(label: Text('Eye-region attention')),
              ],
              rows: [
                for (final s in items)
                  DataRow(
                    key: ValueKey('session-${s.id}'),
                    onSelectChanged: (_) => onOpen(s),
                    cells: [
                      DataCell(Text(
                        s.participantCode,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontFamilyFallback: kMonospaceFallback,
                          fontWeight: FontWeight.w600,
                        ),
                      )),
                      DataCell(Text(formatTimestamp(s.createdAt))),
                      DataCell(Text(sessionStatusLabel(s.status))),
                      DataCell(QualityBadge(quality: s.quality)),
                      DataCell(SyntheticBadge(synthetic: s.synthetic)),
                      DataCell(Text(s.calibrationResidualPx == null
                          ? '—'
                          : '${s.calibrationResidualPx!.round()} px')),
                      DataCell(ValidationBadge(passed: s.validationPassed)),
                      DataCell(Text(formatPercent(s.coverage.classifiableShare))),
                      DataCell(Text(eyeAttentionText(s.eyeRegionAttention))),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
