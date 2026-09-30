import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../ai/presentation/ai_widgets.dart' show MutedText;
import '../../sessions/presentation/session_widgets.dart'
    show QualityBadge, ValidationBadge;
import '../application/pilot_report_controller.dart';
import 'observations_panel.dart';
import 'pilot_widgets.dart';

/// Report: the pilot summary of the study for the research team: sessions,
/// validation and quality, devices, comfort, the debrief answers, the
/// supervisor observations and one row per session. The CSV has every column.
class ReportSection extends StatelessWidget {
  const ReportSection({super.key, required this.controller});

  final PilotReportController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, controller.downloads]),
      builder: (context, _) {
        final c = controller;
        final d = c.downloads;
        final r = c.report;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.error != null) ...[
              MessageBanner(
                key: const Key('report-error'),
                message: c.error!,
                onDismiss: c.dismissError,
              ),
              const SizedBox(height: 12),
            ] else if (d.error != null) ...[
              MessageBanner(
                key: const Key('report-download-error'),
                message: d.error!,
                onDismiss: d.dismissError,
              ),
              const SizedBox(height: 12),
            ] else if (d.notice != null) ...[
              MessageBanner(
                key: const Key('report-download-notice'),
                kind: BannerKind.success,
                message: d.notice!,
                onDismiss: d.dismissNotice,
              ),
              const SizedBox(height: 12),
            ],
            PilotCard(
              title: 'Pilot report',
              caption: 'What the recorded sessions show, under research codes. '
                  'Numbers from synthetic estimators are left out unless you '
                  'include them on purpose.',
              trailing: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('report-refresh'),
                    onPressed: c.loading ? null : c.load,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh'),
                  ),
                  FilledButton.icon(
                    key: const Key('report-download'),
                    onPressed: d.busy || r == null ? null : c.downloadCsv,
                    icon: const Icon(Icons.download, size: 18),
                    label: Text(d.busy ? 'Downloading...' : 'Download CSV'),
                  ),
                ],
              ),
              children: [
                SwitchListTile(
                  key: const Key('report-include-synthetic'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include synthetic sessions'),
                  subtitle: const Text(
                    'Sessions from the development estimator mean nothing '
                    'for measurement.',
                  ),
                  value: c.includeSynthetic,
                  onChanged: c.loading ? null : c.setIncludeSynthetic,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (r == null)
              c.loading
                  ? const BusyBox()
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        key: const Key('report-retry'),
                        onPressed: c.load,
                        child: const Text('Try again'),
                      ),
                    )
            else
              _ReportBody(report: r),
          ],
        );
      },
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report});

  final PilotReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PilotCard(
          title: 'Summary',
          caption: 'Settings version ${r.settings.version}'
              '${r.includesSynthetic ? ', synthetic sessions included' : r.skippedSynthetic > 0 ? ', ${r.skippedSynthetic} synthetic ${r.skippedSynthetic == 1 ? 'session' : 'sessions'} left out' : ''}.',
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatTile(
                  key: const Key('tile-sessions'),
                  label: 'Sessions',
                  value: '${r.sessions}',
                ),
                StatTile(
                  key: const Key('tile-participants'),
                  label: 'Participants',
                  value: '${r.participants}',
                ),
                StatTile(
                  key: const Key('tile-validation'),
                  label: 'Validation passed',
                  value: '${r.validationPassed} of ${r.validated}',
                  caption: 'sessions with a validation',
                ),
                StatTile(
                  key: const Key('tile-quality-ok'),
                  label: 'Quality OK',
                  value: '${r.quality.ok}',
                ),
                StatTile(
                  key: const Key('tile-quality-review'),
                  label: 'Quality Review',
                  value: '${r.quality.review}',
                ),
                StatTile(
                  key: const Key('tile-quality-exclude'),
                  label: 'Quality Exclude',
                  value: '${r.quality.exclude}',
                ),
                StatTile(
                  key: const Key('tile-ended-early'),
                  label: 'Ended early',
                  value: '${r.endedEarly}',
                ),
              ],
            ),
            if (r.note.isNotEmpty) ...[
              const SizedBox(height: 8),
              MutedText(r.note),
            ],
          ],
        ),
        const SizedBox(height: 12),
        PilotCard(
          title: 'By device',
          children: [
            if (r.byDevice.isEmpty)
              const EmptyNote('No sessions to group.')
            else
              ScrollTable(
                child: DataTable(
                  key: const Key('report-devices'),
                  columnSpacing: 24,
                  columns: const [
                    DataColumn(label: Text('Device')),
                    DataColumn(label: Text('Sessions'), numeric: true),
                    DataColumn(label: Text('Validated'), numeric: true),
                    DataColumn(label: Text('Validation passed'), numeric: true),
                    DataColumn(label: Text('Quality OK'), numeric: true),
                  ],
                  rows: [
                    for (final d in r.byDevice)
                      DataRow(
                        key: ValueKey('report-device-${d.devicePlatform}'),
                        cells: [
                          DataCell(Text(d.devicePlatform)),
                          DataCell(Text('${d.sessions}')),
                          DataCell(Text('${d.validated}')),
                          DataCell(Text('${d.validationPassed}')),
                          DataCell(Text('${d.qualityOk}')),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        PilotCard(
          title: 'Comfort answers per stage',
          caption: 'How often each comfort value (1 = very uncomfortable, '
              '5 = very comfortable) was given at the end of a stage.',
          children: [_ComfortBars(counts: r.comfortStageValues)],
        ),
        const SizedBox(height: 12),
        PilotCard(
          title: 'Questions after a session',
          caption: '${r.debrief.answered} answered, ${r.debrief.skipped} skipped.',
          children: [
            if (r.debrief.questions.isEmpty)
              const EmptyNote('No question has been answered yet.')
            else
              ScrollTable(
                child: DataTable(
                  key: const Key('report-debrief'),
                  columnSpacing: 24,
                  dataRowMinHeight: 52,
                  dataRowMaxHeight: 88,
                  columns: const [
                    DataColumn(label: Text('Question')),
                    DataColumn(label: Text('Answered'), numeric: true),
                    DataColumn(label: Text('Answers')),
                    DataColumn(label: Text('Mean'), numeric: true),
                  ],
                  rows: [
                    for (final q in r.debrief.questions)
                      DataRow(
                        key: ValueKey('debrief-stat-${q.key}'),
                        cells: [
                          DataCell(ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(q.prompt,
                                    maxLines: 2, overflow: TextOverflow.ellipsis),
                                Text(
                                  '${q.key}, ${debriefQuestionTypeLabel(q.type)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          )),
                          DataCell(Text('${q.answered}')),
                          DataCell(Text(
                            q.type == DebriefQuestionType.text
                                ? 'see comments'
                                : _countsText(q),
                          )),
                          DataCell(Text(fmtNum(q.mean))),
                        ],
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text('Comments', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            const MutedText('Free-text answers under the research code.'),
            const SizedBox(height: 8),
            if (r.debrief.comments.isEmpty)
              const EmptyNote('No comments.')
            else
              Column(
                key: const Key('report-comments'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < r.debrief.comments.length; i++) ...[
                    if (i > 0) const Divider(height: 14),
                    _CommentTile(comment: r.debrief.comments[i]),
                  ],
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        PilotCard(
          title: 'Observations',
          caption: '${r.observations.total} '
              '${r.observations.total == 1 ? 'observation' : 'observations'} '
              'by supervisors.',
          children: [
            if (r.observations.byCategory.isNotEmpty) ...[
              _ObservationMatrix(report: r.observations),
              const SizedBox(height: 12),
            ],
            if (r.observations.items.isEmpty)
              const EmptyNote('No observations.')
            else
              Column(
                key: const Key('report-observations'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < r.observations.items.length; i++) ...[
                    if (i > 0) const Divider(height: 14),
                    ObservationTile(
                      observation: r.observations.items[i],
                      showCode: true,
                    ),
                  ],
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        PilotCard(
          title: 'Sessions',
          caption: 'One row per session. The CSV has every column, with one '
              'column per debrief question.',
          children: [_RowsTable(rows: r.rows)],
        ),
      ],
    );
  }

  static String _countsText(DebriefQuestionStat q) {
    final entries = q.counts.entries.toList()
      ..sort((a, b) {
        final x = int.tryParse(a.key);
        final y = int.tryParse(b.key);
        if (x != null && y != null) return x.compareTo(y);
        return a.key.compareTo(b.key);
      });
    String label(String key) => switch (key) {
          'true' when q.type == DebriefQuestionType.yesNo => 'Yes',
          'false' when q.type == DebriefQuestionType.yesNo => 'No',
          _ => key,
        };
    return entries.map((e) => '${label(e.key)}: ${e.value}').join(', ');
  }
}

class _ComfortBars extends StatelessWidget {
  const _ComfortBars({required this.counts});

  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) {
      return const EmptyNote('No stage comfort answers yet.');
    }
    final keys = counts.keys.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    return Column(
      key: const Key('report-comfort'),
      children: [
        for (final k in keys)
          ShareBar(
            key: Key('comfort-$k'),
            label: 'Comfort $k',
            share: total == 0 ? null : counts[k]! / total,
            valueText: '${counts[k]}',
          ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final DebriefComment comment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            CodeText(comment.participantCode),
            Text(
              comment.key,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        SelectableText(comment.text),
      ],
    );
  }
}

class _ObservationMatrix extends StatelessWidget {
  const _ObservationMatrix({required this.report});

  final ReportObservations report;

  @override
  Widget build(BuildContext context) {
    final categories = [
      for (final c in ObservationCategory.all)
        if (report.byCategory.containsKey(c)) c,
      for (final c in report.byCategory.keys)
        if (!ObservationCategory.all.contains(c)) c,
    ];
    return ScrollTable(
      child: DataTable(
        key: const Key('report-observation-matrix'),
        columnSpacing: 24,
        columns: [
          const DataColumn(label: Text('Category')),
          for (final s in ObservationSeverity.all)
            DataColumn(label: Text(observationSeverityLabel(s)), numeric: true),
        ],
        rows: [
          for (final c in categories)
            DataRow(cells: [
              DataCell(Text(observationCategoryLabel(c))),
              for (final s in ObservationSeverity.all)
                DataCell(Text('${report.byCategory[c]?[s] ?? 0}')),
            ]),
        ],
      ),
    );
  }
}

class _RowsTable extends StatelessWidget {
  const _RowsTable({required this.rows});

  final List<PilotReportRow> rows;

  static SessionQuality _quality(PilotReportRow r) => SessionQuality(
        grade: r.quality,
        reasons: [
          for (final x in r.qualityReasons.split(';'))
            if (x.isNotEmpty) x,
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const EmptyNote('No sessions in the report.');
    return ScrollTable(
      child: DataTable(
        key: const Key('report-rows'),
        columnSpacing: 18,
        dataRowMinHeight: 44,
        dataRowMaxHeight: 60,
        columns: const [
          DataColumn(label: Text('Participant')),
          DataColumn(label: Text('Created')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Path')),
          DataColumn(label: Text('Device')),
          DataColumn(label: Text('Estimator')),
          DataColumn(label: Text('Residual px'), numeric: true),
          DataColumn(label: Text('Validation')),
          DataColumn(label: Text('Correct'), numeric: true),
          DataColumn(label: Text('Settings v'), numeric: true),
          DataColumn(label: Text('Quality')),
          DataColumn(label: Text('Stages'), numeric: true),
          DataColumn(label: Text('Decisions')),
          DataColumn(label: Text('Comfort min'), numeric: true),
          DataColumn(label: Text('Comfort mean'), numeric: true),
          DataColumn(label: Text('Low comfort'), numeric: true),
          DataColumn(label: Text('Pauses'), numeric: true),
          DataColumn(label: Text('Ended early')),
          DataColumn(label: Text('Comprehension'), numeric: true),
          DataColumn(label: Text('Number task'), numeric: true),
          DataColumn(label: Text('Debrief')),
          DataColumn(label: Text('Observations'), numeric: true),
          DataColumn(label: Text('Tracker files'), numeric: true),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              key: ValueKey('report-row-${r.sessionId}'),
              cells: [
                DataCell(CodeText(r.participantCode)),
                DataCell(Text(formatTimestamp(r.createdAt))),
                DataCell(Text(
                  sessionOutcomeLabel(r.status, r.endReason),
                )),
                DataCell(Text(r.path ?? '-')),
                DataCell(Text(r.devicePlatform ?? '-')),
                DataCell(Text(
                  '${r.estimator ?? '-'}${r.synthetic ? ' (synthetic)' : ''}',
                )),
                DataCell(Text(fmtNum(r.calibrationResidualPx, decimals: 1))),
                DataCell(ValidationBadge(passed: r.validationPassed)),
                DataCell(Text(formatPercent(r.validationCorrectRatio))),
                DataCell(Text(r.settingsVersion == null ? '-' : '${r.settingsVersion}')),
                DataCell(QualityBadge(quality: _quality(r))),
                DataCell(Text(r.stagesCompleted == null ? '-' : '${r.stagesCompleted}')),
                DataCell(Text(r.stageDecisions.isEmpty ? '-' : r.stageDecisions)),
                DataCell(Text(fmtNum(r.comfortMin))),
                DataCell(Text(fmtNum(r.comfortMean, decimals: 2))),
                DataCell(Text(r.comfortLowCount == null ? '-' : '${r.comfortLowCount}')),
                DataCell(Text(r.pauses == null ? '-' : '${r.pauses}')),
                DataCell(Text(r.endedEarly == null ? '-' : (r.endedEarly! ? 'Yes' : 'No'))),
                DataCell(Text(formatPercent(r.comprehensionShare))),
                DataCell(Text(formatPercent(r.numberTaskShare))),
                DataCell(Text(r.debrief)),
                DataCell(Text(
                  r.observationsMajorOrStop > 0
                      ? '${r.observations} (${r.observationsMajorOrStop} major or stop)'
                      : '${r.observations}',
                )),
                DataCell(Text('${r.referenceRecordings}')),
              ],
            ),
        ],
      ),
    );
  }
}
