import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_scope.dart';
import '../../exports/presentation/data_dictionary_dialog.dart';
import '../../sessions/presentation/session_widgets.dart';
import '../application/analysis_controller.dart';
import '../domain/analysis_filters.dart';
import 'trend_chart.dart';

/// The change of the eye share from baseline to post as a signed number of
/// percentage points, `+12 pp`, `-5 pp` or `0 pp`; "Not evaluable" when the
/// session has no eye shares.
String formatEyeShareDelta(double? delta) {
  if (delta == null) return 'Not evaluable';
  final points = (delta * 100).round();
  if (points == 0) return '0 pp';
  return '${points > 0 ? '+' : ''}$points pp';
}

/// The Analysis tab: filters, the result table, comparable groups, one
/// trend card per participant and group, and the exports.
class AnalysisTab extends StatefulWidget {
  const AnalysisTab({super.key, required this.studyId});

  final int studyId;

  @override
  State<AnalysisTab> createState() => _AnalysisTabState();
}

class _AnalysisTabState extends State<AnalysisTab>
    with AutomaticKeepAliveClientMixin {
  late final AnalysisController _controller;
  final _participant = TextEditingController();
  final _version = TextEditingController();
  final _device = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final deps = AppScope.read(context);
    _controller = AnalysisController(
      deps.analysis,
      deps.exports,
      widget.studyId,
      deps.saveFile,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final c in [_participant, _version, _device, _from, _to]) {
      c.dispose();
    }
    super.dispose();
  }

  void _reset() {
    for (final c in [_participant, _version, _device, _from, _to]) {
      c.clear();
    }
    _controller.resetFilters();
  }

  Future<void> _pickDate(TextEditingController field, ValueChanged<String> set) async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(field.text.trim()) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    String two(int n) => n.toString().padLeft(2, '0');
    final text = '${picked.year}-${two(picked.month)}-${two(picked.day)}';
    field.text = text;
    set(text);
  }

  Future<void> _showDictionary() async {
    final entries = await _controller.loadDictionary();
    if (entries != null && mounted) {
      await DataDictionaryDialog.show(context, entries);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        final result = c.response;
        return PageFrame(
          maxWidth: 1200,
          buildAll: true,
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
            Text('Analysis', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Sessions are compared only within one comparable group. Every '
              'analysis view and export is written to the access log.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            _FiltersCard(
              controller: c,
              participant: _participant,
              version: _version,
              device: _device,
              from: _from,
              to: _to,
              onPickFrom: () => _pickDate(_from, c.setFrom),
              onPickTo: () => _pickDate(_to, c.setTo),
              onReset: _reset,
            ),
            const SizedBox(height: 12),
            _ExportsCard(controller: c, onDictionary: _showDictionary),
            const SizedBox(height: 12),
            if (result == null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    c.loading
                        ? 'Loading...'
                        : 'Choose the filters and press "Show analysis". '
                            'Nothing is loaded before that.',
                    key: const Key('analysis-hint'),
                  ),
                ),
              )
            else ...[
              _Summary(result: result),
              const SizedBox(height: 12),
              _ResultsTable(rows: result.rows),
              const SizedBox(height: 16),
              _GroupsSection(result: result),
              const SizedBox(height: 16),
              _TrendsSection(result: result),
            ],
          ],
        );
      },
    );
  }
}

// --------------------------------------------------------------- filters

class _FiltersCard extends StatelessWidget {
  const _FiltersCard({
    required this.controller,
    required this.participant,
    required this.version,
    required this.device,
    required this.from,
    required this.to,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onReset,
  });

  final AnalysisController controller;
  final TextEditingController participant;
  final TextEditingController version;
  final TextEditingController device;
  final TextEditingController from;
  final TextEditingController to;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    final f = c.filters;
    Widget field(Widget child) => SizedBox(width: 200, child: child);
    return Card(
      key: const Key('analysis-filters'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filters', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                field(TextField(
                  key: const Key('filter-participant'),
                  controller: participant,
                  decoration: const InputDecoration(labelText: 'Participant code'),
                  onChanged: c.setParticipant,
                )),
                field(DropdownButtonFormField<String?>(
                  key: const Key('filter-path'),
                  initialValue: f.path,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Path'),
                  items: [
                    const DropdownMenuItem<String?>(child: Text('Both paths')),
                    for (final p in ProtocolPath.values)
                      DropdownMenuItem<String?>(value: p.wire, child: Text(p.label)),
                  ],
                  onChanged: c.setPath,
                )),
                field(TextField(
                  key: const Key('filter-version'),
                  controller: version,
                  decoration: const InputDecoration(labelText: 'Protocol version'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: c.setProtocolVersion,
                )),
                field(TextField(
                  key: const Key('filter-device'),
                  controller: device,
                  decoration: const InputDecoration(
                    labelText: 'Device platform',
                    hintText: 'web, android ...',
                  ),
                  onChanged: c.setDevice,
                )),
                field(TextField(
                  key: const Key('filter-from'),
                  controller: from,
                  decoration: InputDecoration(
                    labelText: 'From (yyyy-mm-dd)',
                    suffixIcon: IconButton(
                      key: const Key('pick-from'),
                      tooltip: 'Pick a date',
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      onPressed: onPickFrom,
                    ),
                  ),
                  onChanged: c.setFrom,
                )),
                field(TextField(
                  key: const Key('filter-to'),
                  controller: to,
                  decoration: InputDecoration(
                    labelText: 'To (yyyy-mm-dd)',
                    suffixIcon: IconButton(
                      key: const Key('pick-to'),
                      tooltip: 'Pick a date',
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      onPressed: onPickTo,
                    ),
                  ),
                  onChanged: c.setTo,
                )),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Quality', style: theme.textTheme.labelLarge),
                for (final g in AnalysisFilters.selectableQualities)
                  FilterChip(
                    key: Key('filter-quality-$g'),
                    label: Text(qualityGradeLabel(g)),
                    selected: f.qualities.contains(g),
                    onSelected: (on) => c.toggleQuality(g, on),
                  ),
              ],
            ),
            SwitchListTile(
              key: const Key('filter-synthetic'),
              value: f.includeSynthetic,
              onChanged: c.setIncludeSynthetic,
              contentPadding: EdgeInsets.zero,
              title: const Text('Include synthetic sessions'),
              subtitle: const Text(
                'Synthetic sessions come from the development estimator and '
                'never support a measurement claim. They are always graded '
                'Exclude, so switching this on also lists sessions graded '
                'Exclude.',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('apply-filters'),
                  onPressed: c.loading ? null : c.apply,
                  icon: const Icon(Icons.search, size: 18),
                  label: Text(c.loading ? 'Loading...' : 'Show analysis'),
                ),
                OutlinedButton(
                  key: const Key('reset-filters'),
                  onPressed: c.loading ? null : onReset,
                  child: const Text('Reset filters'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- exports

class _ExportsCard extends StatelessWidget {
  const _ExportsCard({required this.controller, required this.onDictionary});

  final AnalysisController controller;
  final VoidCallback onDictionary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    final busy = c.downloads.busy;
    return Card(
      key: const Key('analysis-exports'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Exports', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'The session exports use the filters above. Login emails never '
              'appear in an export.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const Key('export-sessions-csv'),
                  onPressed: busy ? null : c.downloadSessionsCsv,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Sessions CSV'),
                ),
                OutlinedButton.icon(
                  key: const Key('export-sessions-json'),
                  onPressed: busy ? null : c.downloadSessionsJson,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Sessions JSON'),
                ),
                OutlinedButton.icon(
                  key: const Key('open-dictionary'),
                  onPressed: c.dictionaryLoading ? null : onDictionary,
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: Text(c.dictionaryLoading ? 'Loading...' : 'Data dictionary'),
                ),
                if (busy)
                  Text('Preparing ${c.downloads.busyLabel}...',
                      key: const Key('export-busy')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- results

class _Summary extends StatelessWidget {
  const _Summary({required this.result});

  final AnalysisResponse result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Results', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          '${result.rows.length} session${result.rows.length == 1 ? '' : 's'} shown'
          ' · ${result.excluded} left out by the quality and synthetic filters',
          key: const Key('analysis-summary'),
          style: muted,
        ),
        if (result.note.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(result.note, key: const Key('analysis-note'), style: muted),
        ],
      ],
    );
  }
}

class _ResultsTable extends StatelessWidget {
  const _ResultsTable({required this.rows});

  final List<AnalysisRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No session matches these filters.',
            key: Key('analysis-empty'),
          ),
        ),
      );
    }
    final shown = rows.length > AnalysisController.displayLimit
        ? rows.sublist(0, AnalysisController.displayLimit)
        : rows;
    String pct(double? v) => formatPercent(v);
    String num1(double? v) => v == null ? '—' : v.toStringAsFixed(1);
    String yesNo(bool? v) => v == null ? '—' : (v ? 'Yes' : 'No');
    const mono = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: kMonospaceFallback,
      fontSize: 12,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  key: const Key('analysis-table'),
                  columnSpacing: 16,
                  dataRowMinHeight: 40,
                  dataRowMaxHeight: 60,
                  headingRowHeight: 44,
                  columns: const [
                    DataColumn(label: Text('Participant')),
                    DataColumn(label: Text('Created')),
                    DataColumn(label: Text('Path')),
                    DataColumn(label: Text('Protocol')),
                    DataColumn(label: Text('Device')),
                    DataColumn(label: Text('Estimator')),
                    DataColumn(label: Text('Quality')),
                    DataColumn(label: Text('Total'), numeric: true),
                    DataColumn(label: Text('Classifiable'), numeric: true),
                    DataColumn(label: Text('Uncertain'), numeric: true),
                    DataColumn(label: Text('Missing'), numeric: true),
                    DataColumn(label: Text('Face'), numeric: true),
                    DataColumn(label: Text('Eye'), numeric: true),
                    DataColumn(label: Text('Baseline eye'), numeric: true),
                    DataColumn(label: Text('Post eye'), numeric: true),
                    DataColumn(label: Text('Eye share change')),
                    DataColumn(label: Text('Comprehension'), numeric: true),
                    DataColumn(label: Text('Number task'), numeric: true),
                    DataColumn(label: Text('Stages'), numeric: true),
                    DataColumn(label: Text('Comfort mean'), numeric: true),
                    DataColumn(label: Text('Comfort min'), numeric: true),
                    DataColumn(label: Text('Low'), numeric: true),
                    DataColumn(label: Text('Pauses'), numeric: true),
                    DataColumn(label: Text('Calibration'), numeric: true),
                    DataColumn(label: Text('Validation')),
                    DataColumn(label: Text('Ended early')),
                    DataColumn(label: Text('Improvement')),
                    DataColumn(label: Text('Group')),
                  ],
                  rows: [
                    for (final r in shown)
                      DataRow(
                        key: ValueKey('analysis-row-${r.sessionId}'),
                        cells: [
                          DataCell(Text(r.participantCode,
                              style: mono.copyWith(fontWeight: FontWeight.w600, fontSize: 13))),
                          DataCell(Text(formatTimestamp(r.createdAt))),
                          DataCell(Text(
                            ProtocolPath.maybeFromWire(r.path)?.label ?? r.path ?? '—',
                          )),
                          DataCell(Text(r.protocolName == null
                              ? '—'
                              : '${r.protocolName} v${r.protocolVersion ?? '?'}')),
                          DataCell(Text(r.devicePlatform ?? '—')),
                          DataCell(Text(
                            '${r.estimator ?? '—'}${r.synthetic ? ' (synthetic)' : ''}',
                          )),
                          DataCell(QualityBadge(quality: r.qualityInfo)),
                          DataCell(Text(r.totalMs == null ? '—' : formatDurationMs(r.totalMs!))),
                          DataCell(Text(pct(r.classifiableShare))),
                          DataCell(Text(pct(r.uncertainShare))),
                          DataCell(Text(pct(r.missingShare))),
                          DataCell(Text(pct(r.faceShare))),
                          DataCell(Text(pct(r.eyeShare))),
                          DataCell(Text(pct(r.baselineEyeShare))),
                          DataCell(Text(pct(r.postEyeShare))),
                          DataCell(_DeltaCell(delta: r.eyeShareDelta, sessionId: r.sessionId)),
                          DataCell(Text(pct(r.comprehensionShare))),
                          DataCell(Text(pct(r.numberTaskShare))),
                          DataCell(Text(r.stagesCompleted?.toString() ?? '—')),
                          DataCell(Text(num1(r.comfortMean))),
                          DataCell(Text(r.comfortMin?.toString() ?? '—')),
                          DataCell(Text(r.comfortLowCount?.toString() ?? '—')),
                          DataCell(Text(r.pauses?.toString() ?? '—')),
                          DataCell(Text(r.calibrationResidualPx == null
                              ? '—'
                              : '${r.calibrationResidualPx!.round()} px')),
                          DataCell(ValidationBadge(passed: r.validationPassed)),
                          DataCell(Text(r.endedEarly ? 'Yes' : 'No')),
                          DataCell(Text(r.improvement == null
                              ? 'Cannot be judged'
                              : yesNo(r.improvement))),
                          DataCell(ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Text(
                              r.groupKey.isEmpty ? '—' : r.groupKey,
                              style: mono,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (rows.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Showing the first ${shown.length} of ${rows.length} sessions; '
              'the export has all of them.',
              key: const Key('analysis-row-limit'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// The eye share change with its sign, tinted: an increase green, a
/// decrease amber, no change neutral. The sign is in the text, so colour is
/// never the only cue.
class _DeltaCell extends StatelessWidget {
  const _DeltaCell({required this.delta, required this.sessionId});

  final double? delta;
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    final d = delta;
    final (fg, bg) = d == null
        ? (AppColors.textMuted, Colors.transparent)
        : (d * 100).round() > 0
            ? (AppColors.success, AppColors.successTint)
            : (d * 100).round() < 0
                ? (AppColors.warning, AppColors.warningTint)
                : (AppColors.text, AppColors.background);
    return Container(
      key: Key('delta-$sessionId'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Text(
        formatEyeShareDelta(d),
        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ---------------------------------------------------------------- groups

class _GroupsSection extends StatelessWidget {
  const _GroupsSection({required this.result});

  final AnalysisResponse result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('groups-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Comparable groups', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          result.note.isEmpty
              ? 'Sessions from different groups are never pooled.'
              : result.note,
          key: const Key('groups-note'),
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        if (result.groups.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No comparable group yet.'),
            ),
          )
        else
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < result.groups.length; i++) ...[
                  if (i > 0) const Divider(),
                  _GroupTile(group: result.groups[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group});

  final AnalysisGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: Key('group-${group.groupKey}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${group.sessions} session${group.sessions == 1 ? '' : 's'} · '
            '${group.participants} participant${group.participants == 1 ? '' : 's'}',
            style: theme.textTheme.titleSmall,
          ),
          Text(TrendCard.groupText(group, group.groupKey)),
          Text(
            group.groupKey,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: kMonospaceFallback,
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- trends

class _TrendsSection extends StatelessWidget {
  const _TrendsSection({required this.result});

  final AnalysisResponse result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = {for (final g in result.groups) g.groupKey: g};
    return Column(
      key: const Key('trends-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Trends per participant', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'One card per participant and comparable group, sessions in date '
          'order. The bars are shares of classifiable time on the eye region.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        if (result.trends.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No trend to show.'),
            ),
          )
        else
          LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 3
                : (constraints.maxWidth >= 560 ? 2 : 1);
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final t in result.trends)
                  SizedBox(
                    width: width,
                    child: TrendCard(trend: t, group: groups[t.groupKey]),
                  ),
              ],
            );
          }),
      ],
    );
  }
}
