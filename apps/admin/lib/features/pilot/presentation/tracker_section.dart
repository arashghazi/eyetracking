import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../ai/presentation/ai_widgets.dart' show MutedText;
import '../application/tracker_comparison_controller.dart';
import 'pilot_widgets.dart';

/// Tracker comparison: import the export of a research eye tracker for a
/// session and compare its gaze points with the webcam estimate. The numbers
/// describe that session on that computer only; the caveats say what weakens
/// them. Analysts can compare; only researchers import.
class TrackerSection extends StatelessWidget {
  const TrackerSection({super.key, required this.controller});

  final TrackerComparisonController controller;

  static const originHelp =
      "Run the Participant App full screen (F11) on the tracker's screen so "
      'origin is 0, 0.';

  static String sessionLabel(SessionListItem s) =>
      '${s.participantCode}, ${formatTimestamp(s.createdAt)}, '
      '${sessionStatusLabel(s.status)}${s.synthetic ? ', synthetic' : ''}';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SessionPicker(controller: c),
            if (c.selectedId != null) ...[
              if (c.canImport) ...[
                const SizedBox(height: 12),
                _ImportCard(controller: c),
              ],
              const SizedBox(height: 12),
              _RecordingsCard(controller: c),
              if (c.comparison != null) ...[
                const SizedBox(height: 12),
                ComparisonCard(comparison: c.comparison!),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _SessionPicker extends StatelessWidget {
  const _SessionPicker({required this.controller});

  final TrackerComparisonController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return PilotCard(
      title: 'Session',
      caption: 'Pick the session that was recorded with the webcam and the '
          "research tracker at the same time. Each comparison is about that "
          'one session on that one computer.',
      trailing: OutlinedButton.icon(
        key: const Key('tracker-reload'),
        onPressed: c.sessionsLoading ? null : c.loadSessions,
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('Reload'),
      ),
      children: [
        if (c.sessionsError != null)
          MessageBanner(key: const Key('tracker-sessions-error'), message: c.sessionsError!)
        else if (c.sessionsLoading && !c.sessionsLoaded)
          const BusyBox()
        else if (c.sessions.isEmpty)
          const EmptyNote('No sessions yet. They appear here after a participant '
              'starts one in the Participant App.')
        else
          DropdownButtonFormField<String>(
            key: const Key('tracker-session'),
            initialValue: c.selectedId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Session'),
            items: [
              for (final s in c.sessions)
                DropdownMenuItem(
                  value: s.id,
                  child: Text(
                    TrackerSection.sessionLabel(s),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: c.selectSession,
          ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.fieldKey,
    required this.label,
    this.helper,
    this.width = 220,
    this.numeric = false,
  });

  final TrackerComparisonController controller;
  final String fieldKey;
  final String label;
  final String? helper;
  final double width;
  final bool numeric;

  @override
  Widget build(BuildContext context) => WrapItem(
        width: width,
        child: TextFormField(
          key: Key('tracker-$fieldKey'),
          initialValue: controller.value(fieldKey),
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true, signed: true)
              : TextInputType.text,
          decoration: InputDecoration(
            labelText: label,
            helperText: helper,
            helperMaxLines: 3,
            errorText: controller.errorFor(fieldKey),
            errorMaxLines: 2,
          ),
          onChanged: (v) => controller.setValue(fieldKey, v),
        ),
      );
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width = 220,
  });

  final String fieldKey;
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) => WrapItem(
        width: width,
        child: DropdownButtonFormField<T>(
          key: Key('tracker-$fieldKey'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final e in items.entries)
              DropdownMenuItem<T>(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      );
}

class _ImportCard extends StatelessWidget {
  const _ImportCard({required this.controller});

  final TrackerComparisonController controller;

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final file = c.file;
    return PilotCard(
      key: const Key('tracker-import-card'),
      title: 'Import a tracker export',
      caption: 'A CSV or TSV file with one row per gaze sample. The columns '
          'below name the fields in that file.',
      children: [
        Container(
          key: const Key('tracker-origin-help'),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.tealTint,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(kRadius),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: AppColors.tealDark),
              SizedBox(width: 8),
              Expanded(child: Text(TrackerSection.originHelp)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const Key('tracker-pick-file'),
              onPressed: c.importing ? null : c.pickFile,
              icon: const Icon(Icons.upload_file, size: 18),
              label: Text(file == null ? 'Choose file' : 'Choose another file'),
            ),
            if (file != null)
              Text(
                '${file.name} (${_size(file.bytes.length)})',
                key: const Key('tracker-file-name'),
                style: theme.textTheme.bodyMedium,
              ),
          ],
        ),
        if (c.errorFor('file') != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              c.errorFor('file')!,
              key: const Key('tracker-file-error'),
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            _Field(
              controller: c,
              fieldKey: 'source',
              label: 'Tracker name and model',
              width: 300,
            ),
            _Field(controller: c, fieldKey: 'time_column', label: 'Time column'),
            _Field(controller: c, fieldKey: 'x_column', label: 'X column'),
            _Field(controller: c, fieldKey: 'y_column', label: 'Y column'),
            _Field(
              controller: c,
              fieldKey: 'valid_column',
              label: 'Valid column (optional)',
              helper: 'Leave empty when every row is a valid sample.',
            ),
            _Field(
              controller: c,
              fieldKey: 'valid_values',
              label: 'Valid values (optional)',
              helper: 'Comma list. Default: 1,true,valid,yes',
            ),
            _Choice<String>(
              fieldKey: 'time_unit',
              label: 'Time unit',
              value: c.timeUnit,
              items: const {
                ReferenceTimeUnit.ms: 'Milliseconds (ms)',
                ReferenceTimeUnit.us: 'Microseconds (us)',
                ReferenceTimeUnit.s: 'Seconds (s)',
              },
              onChanged: c.setTimeUnit,
            ),
            _Field(
              controller: c,
              fieldKey: 'offset',
              label: 'Offset',
              helper: 'Tracker time at session time 0, in the time unit.',
              numeric: true,
            ),
            _Choice<String>(
              fieldKey: 'coord_space',
              label: 'Coordinate space',
              value: c.coordSpace,
              items: const {
                ReferenceCoordSpace.cssPx: 'CSS pixels',
                ReferenceCoordSpace.devicePx: 'Device pixels',
                ReferenceCoordSpace.norm: 'Normalised (0 to 1)',
              },
              onChanged: c.setCoordSpace,
            ),
            _Field(
              controller: c,
              fieldKey: 'origin_x',
              label: 'Origin x (CSS px)',
              width: 150,
              numeric: true,
            ),
            _Field(
              controller: c,
              fieldKey: 'origin_y',
              label: 'Origin y (CSS px)',
              width: 150,
              numeric: true,
            ),
            _Choice<String>(
              fieldKey: 'delimiter',
              label: 'Delimiter',
              value: c.delimiter,
              width: 160,
              items: {
                for (final d in TrackerComparisonController.delimiters) d.$1: d.$2,
              },
              onChanged: c.setDelimiter,
            ),
            _Field(
              controller: c,
              fieldKey: 'auto_align_window_ms',
              label: 'Auto-align window (ms)',
              helper: '0 = off, at most 10000. An alignment estimated from the '
                  'same data makes the agreement look better than it is.',
              width: 300,
              numeric: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (c.importError != null) ...[
          MessageBanner(
            key: const Key('tracker-import-error'),
            message: c.importError!,
            onDismiss: c.dismissImportError,
          ),
          const SizedBox(height: 8),
        ] else if (c.notice != null) ...[
          MessageBanner(
            key: const Key('tracker-import-notice'),
            kind: BannerKind.success,
            message: c.notice!,
            onDismiss: c.dismissNotice,
          ),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const Key('tracker-import'),
            onPressed: c.importing ? null : c.importFile,
            icon: const Icon(Icons.file_upload_outlined, size: 18),
            label: Text(c.importing ? 'Importing...' : 'Import'),
          ),
        ),
      ],
    );
  }
}

class _RecordingsCard extends StatelessWidget {
  const _RecordingsCard({required this.controller});

  final TrackerComparisonController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return PilotCard(
      title: 'Imported recordings',
      caption: 'Compare pairs each webcam sample with the nearest tracker '
          'sample in time, within the tolerance.',
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            WrapItem(
              width: 180,
              child: TextFormField(
                key: const Key('tracker-tolerance'),
                initialValue: c.tolerance,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Tolerance (ms)',
                  helperText: '1 to 500, default 40',
                  errorText: c.toleranceError,
                  errorMaxLines: 2,
                ),
                onChanged: c.setTolerance,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (c.recordingsError != null)
          MessageBanner(key: const Key('tracker-recordings-error'), message: c.recordingsError!)
        else if (c.recordingsLoading && c.recordings.isEmpty)
          const BusyBox()
        else if (c.recordings.isEmpty)
          const EmptyNote('No tracker export has been imported for this session.')
        else if (c.compareError != null)
          MessageBanner(key: const Key('tracker-compare-error'), message: c.compareError!),
        if (c.compareError != null && c.recordingsError == null && c.recordings.isNotEmpty)
          const SizedBox(height: 8),
        if (c.recordingsError == null && c.recordings.isNotEmpty)
          Column(
            key: const Key('tracker-recordings'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < c.recordings.length; i++) ...[
                if (i > 0) const Divider(height: 12),
                Container(
                  key: Key('recording-${c.recordings[i].id}'),
                  color: c.recordings[i].id == c.comparedId ? AppColors.tealTint : null,
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        c.recordings[i].source,
                        style: theme.textTheme.labelLarge,
                      ),
                      Text(
                        '${c.recordings[i].sampleCount} samples, '
                        '${c.recordings[i].validCount} valid',
                        style: muted,
                      ),
                      Text(
                        c.recordings[i].alignmentEstimated
                            ? 'Alignment estimated from the data'
                                '${c.recordings[i].estimatedShiftMs == null ? '' : ' (shift ${fmtSigned(c.recordings[i].estimatedShiftMs)} ms)'}'
                            : 'Alignment from the given offset',
                        style: muted,
                      ),
                      Text(formatTimestamp(c.recordings[i].createdAt), style: muted),
                      FilledButton(
                        key: Key('compare-${c.recordings[i].id}'),
                        onPressed: c.comparingId != null
                            ? null
                            : () => c.compare(c.recordings[i]),
                        child: Text(
                          c.comparingId == c.recordings[i].id
                              ? 'Comparing...'
                              : 'Compare',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

/// The result of one comparison: agreement, distances, the confusion matrix,
/// per-segment eye shares and, prominently, the caveats.
class ComparisonCard extends StatelessWidget {
  const ComparisonCard({super.key, required this.comparison});

  final ReferenceComparison comparison;

  @override
  Widget build(BuildContext context) {
    final r = comparison;
    final theme = Theme.of(context);
    final rec = r.recording;
    final screen = r.session.screen;
    return PilotCard(
      key: const Key('comparison-card'),
      title: 'Comparison',
      caption: '${r.session.participantCode}'
          '${rec == null ? '' : ' with ${rec.source}'}, tolerance ${r.toleranceMs} ms.',
      children: [
        if (r.caveats.isNotEmpty) ...[
          WarningBox(
            key: const Key('comparison-caveats'),
            title: 'Read these numbers with care',
            lines: r.caveats,
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatTile(
              key: const Key('cmp-agreement'),
              label: 'Region agreement',
              value: formatPercent(r.regionAgreement),
              caption: 'of ${r.pairedClassified} paired samples',
            ),
            StatTile(
              key: const Key('cmp-kappa'),
              label: "Cohen's kappa",
              value: fmtNum(r.cohenKappa),
              caption: 'agreement beyond chance',
            ),
            StatTile(
              key: const Key('cmp-eye-precision'),
              label: 'Eye precision',
              value: formatPercent(r.eyePrecision),
              caption: 'webcam eye that tracker calls eye',
            ),
            StatTile(
              key: const Key('cmp-eye-recall'),
              label: 'Eye recall',
              value: formatPercent(r.eyeRecall),
              caption: 'tracker eye that webcam finds',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Counts', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          key: const Key('cmp-counts'),
          spacing: 8,
          runSpacing: 8,
          children: [
            StatTile(label: 'Webcam samples', value: '${r.webcamSamples}', width: 190),
            StatTile(label: 'Paired and classified', value: '${r.pairedClassified}', width: 190),
            StatTile(
              label: 'Webcam uncertain',
              value: '${r.webcamUncertainWhileReferenceValid}',
              caption: 'while the tracker was valid',
              width: 190,
            ),
            StatTile(label: 'Tracker invalid', value: '${r.referenceInvalid}', width: 190),
            StatTile(
              label: 'No tracker sample in time',
              value: '${r.noReferenceInTime}',
              width: 190,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Distance between the points (CSS px)', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        ScrollTable(
          child: DataTable(
            key: const Key('cmp-distance'),
            columnSpacing: 22,
            columns: const [
              DataColumn(label: Text('n'), numeric: true),
              DataColumn(label: Text('Min'), numeric: true),
              DataColumn(label: Text('p25'), numeric: true),
              DataColumn(label: Text('Median'), numeric: true),
              DataColumn(label: Text('p75'), numeric: true),
              DataColumn(label: Text('p90'), numeric: true),
              DataColumn(label: Text('Max'), numeric: true),
            ],
            rows: [
              DataRow(cells: [
                DataCell(Text('${r.distancePx.n}')),
                DataCell(Text(fmtNum(r.distancePx.min))),
                DataCell(Text(fmtNum(r.distancePx.p25))),
                DataCell(Text(fmtNum(r.distancePx.median))),
                DataCell(Text(fmtNum(r.distancePx.p75))),
                DataCell(Text(fmtNum(r.distancePx.p90))),
                DataCell(Text(fmtNum(r.distancePx.max))),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          r.biasX == null && r.biasY == null
              ? 'Bias: no paired points.'
              : 'Bias (webcam minus tracker): x ${fmtSigned(r.biasX)} px, '
                  'y ${fmtSigned(r.biasY)} px.',
          key: const Key('cmp-bias'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Text('Confusion matrix', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        const MutedText('Rows are what the webcam said, columns what the tracker said.'),
        const SizedBox(height: 8),
        _ConfusionTable(matrix: r.confusion),
        const SizedBox(height: 16),
        Text('Eye share per segment', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (r.segments.isEmpty)
          const EmptyNote('No segments were paired.')
        else
          ScrollTable(
            child: DataTable(
              key: const Key('cmp-segments'),
              columnSpacing: 24,
              columns: const [
                DataColumn(label: Text('Segment')),
                DataColumn(label: Text('Pairs'), numeric: true),
                DataColumn(label: Text('Webcam eye share'), numeric: true),
                DataColumn(label: Text('Tracker eye share'), numeric: true),
              ],
              rows: [
                for (final s in r.segments)
                  DataRow(
                    key: ValueKey('cmp-segment-${s.segment}'),
                    cells: [
                      DataCell(Text(s.segment)),
                      DataCell(Text('${s.pairs}')),
                      DataCell(Text(formatPercent(s.webcamEyeShare))),
                      DataCell(Text(formatPercent(s.referenceEyeShare))),
                    ],
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            Text('Estimator: ${r.session.estimator ?? '-'}'
                '${r.session.gazeModelVersion == null ? '' : ' ${r.session.gazeModelVersion}'}'),
            Text('Validation: ${r.session.validationPassed ? 'passed' : 'not passed'}'),
            if (screen['w'] != null && screen['h'] != null)
              Text('Screen: ${screen['w']} x ${screen['h']}'),
          ],
        ),
        if (r.note.isNotEmpty) ...[
          const SizedBox(height: 8),
          MutedText(r.note),
        ],
      ],
    );
  }
}

class _ConfusionTable extends StatelessWidget {
  const _ConfusionTable({required this.matrix});

  final ConfusionMatrix matrix;

  @override
  Widget build(BuildContext context) {
    return ScrollTable(
      child: DataTable(
        key: const Key('cmp-confusion'),
        columnSpacing: 24,
        columns: [
          const DataColumn(label: Text('Webcam \\ Tracker')),
          for (final ref in ConfusionMatrix.labels)
            DataColumn(label: Text(regionLabel(ref)), numeric: true),
        ],
        rows: [
          for (final web in ConfusionMatrix.labels)
            DataRow(
              key: ValueKey('cm-row-$web'),
              cells: [
                DataCell(Text(regionLabel(web),
                    style: const TextStyle(fontWeight: FontWeight.w600))),
                for (final ref in ConfusionMatrix.labels)
                  DataCell(
                    Container(
                      key: Key('cm-$web-$ref'),
                      color: web == ref ? AppColors.tealTint : null,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text('${matrix.cell(web, ref)}'),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
