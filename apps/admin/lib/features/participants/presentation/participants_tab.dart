import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../application/participants_controller.dart';
import 'participant_detail_screen.dart';
import 'yes_no.dart';

class ParticipantsTab extends StatefulWidget {
  const ParticipantsTab({
    super.key,
    required this.studyId,
    this.canEdit = true,
  });

  final int studyId;

  /// Researchers may assign protocols; analysts only read.
  final bool canEdit;

  @override
  State<ParticipantsTab> createState() => _ParticipantsTabState();
}

class _ParticipantsTabState extends State<ParticipantsTab>
    with AutomaticKeepAliveClientMixin {
  late final ParticipantsController _controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = ParticipantsController(
      AppScope.read(context).participants,
      widget.studyId,
    );
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open(ParticipantRecord record) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ParticipantDetailScreen(
          studyId: widget.studyId,
          initial: record,
          canEdit: widget.canEdit,
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
          maxWidth: 1100,
          banner: c.error != null
              ? MessageBanner(message: c.error!, onDismiss: c.dismissError)
              : null,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Participants', style: theme.textTheme.titleLarge),
                if (c.loadedOnce)
                  Text(
                    '${c.records.length} total, ${c.readyCount} ready',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                OutlinedButton.icon(
                  key: const Key('reload-participants'),
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
            else if (c.records.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    c.loadedOnce
                        ? 'No participants yet. Create an invitation on the Invitations tab.'
                        : 'Participants could not be loaded.',
                  ),
                ),
              )
            else ...[
              Text(
                'Select a row to see the full coded record.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              _ParticipantsTable(records: c.records, onOpen: _open),
            ],
          ],
        );
      },
    );
  }
}

class _ParticipantsTable extends StatelessWidget {
  const _ParticipantsTable({required this.records, required this.onOpen});

  final List<ParticipantRecord> records;
  final ValueChanged<ParticipantRecord> onOpen;

  static String consentText(Consent? consent) {
    if (consent == null) return 'None';
    return consent.isWithdrawn
        ? '${consent.sheetVersion} (withdrawn)'
        : '${consent.sheetVersion}';
  }

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
              showCheckboxColumn: false,
              columnSpacing: 24,
              dataRowMinHeight: 44,
              dataRowMaxHeight: 72,
              columns: const [
                DataColumn(label: Text('Code')),
                DataColumn(label: Text('Ready')),
                DataColumn(label: Text('Reasons')),
                DataColumn(label: Text('Consent version')),
                DataColumn(label: Text('Demographics complete')),
              ],
              rows: [
                for (final r in records)
                  DataRow(
                    key: ValueKey('participant-${r.code}'),
                    onSelectChanged: (_) => onOpen(r),
                    cells: [
                      DataCell(Text(
                        r.code,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontFamilyFallback: kMonospaceFallback,
                          fontWeight: FontWeight.w600,
                        ),
                      )),
                      DataCell(YesNo(value: r.readiness.ready)),
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Text(
                          r.readiness.reasons.isEmpty
                              ? '-'
                              : r.readiness.reasons
                                  .map(readinessReasonLabel)
                                  .join(', '),
                        ),
                      )),
                      DataCell(Text(consentText(r.consent))),
                      DataCell(YesNo(value: r.demographicsComplete)),
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
