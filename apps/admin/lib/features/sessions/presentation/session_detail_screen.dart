import 'dart:convert';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../exports/application/download_controller.dart';
import '../../exports/domain/exports_repository.dart';
import '../../pilot/presentation/observations_panel.dart';
import '../../replay/presentation/replay_screen.dart';
import '../application/sessions_controller.dart';
import 'session_widgets.dart';

class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({
    super.key,
    required this.studyId,
    required this.sessionId,
    required this.participantCode,
    this.canEdit = false,
  });

  final int studyId;
  final String sessionId;
  final String participantCode;

  /// Researchers add supervisor observations; analysts only read them.
  final bool canEdit;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  late final SessionDetailController _controller;
  late final DownloadController _downloads;
  late final ExportsRepository _exports;

  @override
  void initState() {
    super.initState();
    final deps = AppScope.read(context);
    _controller = SessionDetailController(
      deps.sessions,
      widget.studyId,
      widget.sessionId,
    )..load();
    _exports = deps.exports;
    _downloads = DownloadController(deps.saveFile);
  }

  @override
  void dispose() {
    _controller.dispose();
    _downloads.dispose();
    super.dispose();
  }

  void _openReplay() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReplayScreen(
          studyId: widget.studyId,
          sessionId: widget.sessionId,
          participantCode: widget.participantCode,
        ),
      ),
    );
  }

  Future<void> _downloadSamples() => _downloads.download(
        () => _exports.samplesCsv(widget.studyId, widget.sessionId),
        filename: 'samples-${widget.participantCode}-${widget.sessionId}.csv',
        mimeType: DownloadTypes.csv,
      );

  Future<void> _downloadEvents() => _downloads.download(
        () => _exports.eventsCsv(widget.studyId, widget.sessionId),
        filename: 'events-${widget.participantCode}-${widget.sessionId}.csv',
        mimeType: DownloadTypes.csv,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Session of ${widget.participantCode}'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_controller, _downloads]),
        builder: (context, _) {
          final c = _controller;
          final d = _downloads;
          final detail = c.detail;
          return PageFrame(
            maxWidth: 1200,
            banner: c.error != null
                ? MessageBanner(message: c.error!, onDismiss: c.dismissError)
                : d.error != null
                    ? MessageBanner(message: d.error!, onDismiss: d.dismissError)
                    : d.notice != null
                        ? MessageBanner(
                            message: d.notice!,
                            kind: BannerKind.success,
                            onDismiss: d.dismissNotice,
                          )
                        : null,
            children: [
              if (detail == null)
                c.loading
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton(
                          onPressed: c.load,
                          child: const Text('Try again'),
                        ),
                      )
              else ...[
                _Header(detail: detail, onReplay: _openReplay),
                const SizedBox(height: 12),
                _Cards(summary: detail.summary),
                if (detail.summary.outcomes != null) ...[
                  const SizedBox(height: 12),
                  _ImprovementLine(
                    improvement: detail.summary.outcomes!.improvement,
                  ),
                ],
                if (detail.summary.protocol != null) ...[
                  const SizedBox(height: 12),
                  _ProtocolSection(summary: detail.summary),
                ],
                const SizedBox(height: 12),
                _DeviceSection(detail: detail),
                const SizedBox(height: 12),
                _CalibrationSection(summary: detail.summary),
                const SizedBox(height: 12),
                _ValidationSection(
                  summary: detail.summary,
                  targets: detail.validationTargets,
                ),
                const SizedBox(height: 12),
                _CoverageSection(summary: detail.summary),
                const SizedBox(height: 12),
                _SegmentsSection(summary: detail.summary),
                if (detail.summary.protocol != null) ...[
                  const SizedBox(height: 12),
                  _StagesSection(stages: detail.summary.stages),
                  const SizedBox(height: 12),
                  _TrialsSection(trials: detail.trials),
                  const SizedBox(height: 12),
                  _AnswersSection(answers: detail.answers),
                  const SizedBox(height: 12),
                  _ComfortAnswersSection(
                    answers: detail.comfortAnswers,
                    comfort: detail.summary.protocol?.definition?.comfort,
                  ),
                ],
                const SizedBox(height: 12),
                SessionObservations(
                  key: Key('session-observations-${widget.sessionId}'),
                  studyId: widget.studyId,
                  sessionId: widget.sessionId,
                  canEdit: widget.canEdit,
                ),
                const SizedBox(height: 12),
                _EventsSection(
                  events: detail.events,
                  busy: d.busy,
                  onDownload: _downloadEvents,
                ),
                const SizedBox(height: 12),
                _SamplesSection(
                  controller: c,
                  busy: d.busy,
                  onDownload: _downloadSamples,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------ building blocks

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.keyName});

  final String title;
  final List<Widget> children;
  final String? keyName;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: keyName == null ? null : Key(keyName!),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelText = Text(
      label,
      style: theme.textTheme.bodyMedium
          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
    final valueText = SelectableText(
      value,
      style: mono
          ? const TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: kMonospaceFallback,
            )
          : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [labelText, valueText],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 200, child: labelText),
            Expanded(child: valueText),
          ],
        );
      }),
    );
  }
}

/// Horizontally scrollable bordered table.
class _TableBox extends StatelessWidget {
  const _TableBox({required this.child, this.keyName, this.maxHeight});

  final Widget child;
  final String? keyName;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    Widget table = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: child,
    );
    if (maxHeight != null) {
      table = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight!),
        child: SingleChildScrollView(child: table),
      );
    }
    return Container(
      key: keyName == null ? null : Key(keyName!),
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: table,
    );
  }
}

// -------------------------------------------------------------------- header

class _Header extends StatelessWidget {
  const _Header({required this.detail, required this.onReplay});

  final SessionDetail detail;
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = detail.summary;
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          detail.participantCode,
          style: theme.textTheme.titleLarge?.copyWith(
            fontFamily: 'monospace',
            fontFamilyFallback: kMonospaceFallback,
          ),
        ),
        Text(
          sessionOutcomeLabel(s.status, s.endReason),
          style: theme.textTheme.bodyLarge,
        ),
        Text(
          'Created ${formatTimestamp(s.createdAt)}',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        SyntheticBadge(synthetic: s.synthetic),
        if (s.quality != null)
          KeyedSubtree(
            key: const Key('header-quality'),
            child: QualityBadge(quality: s.quality, compact: false),
          ),
        FilledButton.icon(
          key: const Key('open-replay'),
          onPressed: onReplay,
          icon: const Icon(Icons.play_circle_outline, size: 18),
          label: const Text('Replay'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- four cards

class _Cards extends StatelessWidget {
  const _Cards({required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final eye = summary.eyeRegionAttention;
    final o = summary.outcomes;
    final gradual = summary.protocol?.path == ProtocolPath.gradualFace ||
        (summary.protocol?.path == null &&
            o != null &&
            o.numberTask.trials > 0 &&
            o.comprehension.answered == 0);
    final cards = [
      _MetricCard(
        keyName: 'card-face',
        title: 'Face-region attention',
        value: summary.faceRegionShare == null
            ? '—'
            : formatPercent(summary.faceRegionShare),
        note: 'Share of classifiable time on the face.',
      ),
      _MetricCard(
        keyName: 'card-eye',
        title: 'Eye-region attention',
        value: eyeAttentionText(eye),
        note: eye.evaluable && eye.share != null
            ? 'Share of classifiable time on the eye region.'
            : (eye.reason == null || eye.reason!.isEmpty
                ? 'No reason given.'
                : eye.reason!),
        noteKey: 'eye-reason',
      ),
      if (gradual)
        _numberTaskCard(o!.numberTask)
      else
        _comprehensionCard(o),
      _comfortCard(o),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final columns = w >= 1000 ? 4 : (w >= 560 ? 2 : 1);
      final cardWidth = (w - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [for (final c in cards) SizedBox(width: cardWidth, child: c)],
      );
    });
  }
}

Widget _comprehensionCard(SessionOutcomes? o) {
  if (o == null) {
    return const _MetricCard(
      keyName: 'card-comprehension',
      title: 'Comprehension',
      value: '—',
      note: 'No practice was run in this session.',
    );
  }
  final c = o.comprehension;
  if (c.answered == 0) {
    return const _MetricCard(
      keyName: 'card-comprehension',
      title: 'Comprehension',
      value: '—',
      note: 'No comprehension question was answered.',
    );
  }
  return _MetricCard(
    keyName: 'card-comprehension',
    title: 'Comprehension',
    value: '${c.correct} of ${c.answered}',
    note: '${formatPercent(c.share)} of the questions answered correctly.',
  );
}

Widget _numberTaskCard(NumberTaskOutcome t) {
  if (t.trials == 0) {
    return const _MetricCard(
      keyName: 'card-number-task',
      title: 'Number task',
      value: '—',
      note: 'No number was shown.',
    );
  }
  return _MetricCard(
    keyName: 'card-number-task',
    title: 'Number task',
    value: '${t.correct} of ${t.trials}',
    note: '${formatPercent(t.share)} matched · '
        '${t.stagesCompleted} stage${t.stagesCompleted == 1 ? '' : 's'} completed.',
  );
}

Widget _comfortCard(SessionOutcomes? o) {
  final c = o?.comfort;
  if (c == null || c.answers == 0) {
    return _MetricCard(
      keyName: 'card-comfort',
      title: 'Comfort',
      value: '—',
      note: o == null
          ? 'No practice was run in this session.'
          : (c!.endedEarly
              ? 'No comfort answer was given; the session ended early.'
              : 'No comfort answer was given.'),
    );
  }
  return _MetricCard(
    keyName: 'card-comfort',
    title: 'Comfort',
    value: c.mean == null ? '—' : c.mean!.toStringAsFixed(1),
    note: 'Average of ${c.answers} answers · lowest ${c.min ?? '-'} · '
        '${c.lowCount} low'
        '${c.pauses > 0 ? ' · ${c.pauses} pause${c.pauses == 1 ? '' : 's'}' : ''}'
        '${c.endedEarly ? ' · ended early' : ''}',
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.keyName,
    required this.title,
    required this.value,
    required this.note,
    this.noteKey,
  });

  final String keyName;
  final String title;
  final String value;
  final String note;
  final String? noteKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: Key(keyName),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              note,
              key: noteKey == null ? null : Key(noteKey!),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ sections

/// "All three criteria met", "Not met" or "Cannot be judged yet".
class _ImprovementLine extends StatelessWidget {
  const _ImprovementLine({required this.improvement});

  final ImprovementOutcome improvement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (text, icon, color) = switch (improvement.result) {
      true => ('All three criteria met', Icons.check_circle, AppColors.success),
      false => ('Not met', Icons.remove_circle_outline, AppColors.warning),
      null => (
          'Cannot be judged yet',
          Icons.hourglass_empty,
          AppColors.textMuted
        ),
    };
    final reason = outcomeReasonLabel(improvement.reason);
    String mark(bool? v) => v == null ? 'not known' : (v ? 'yes' : 'no');
    return _Section(
      title: 'Improvement',
      keyName: 'section-improvement',
      children: [
        Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                key: const Key('improvement-text'),
                style: theme.textTheme.titleMedium?.copyWith(color: color),
              ),
            ),
          ],
        ),
        if (improvement.result == null && reason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              reason,
              key: const Key('improvement-reason'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 8),
        _Row('Eye share went up', mark(improvement.eyeShareUp)),
        _Row('Comfort did not get worse', mark(improvement.comfortNotWorse)),
        _Row('Comprehension or number task kept',
            mark(improvement.comprehensionMaintained)),
      ],
    );
  }
}

class _ProtocolSection extends StatelessWidget {
  const _ProtocolSection({required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final p = summary.protocol!;
    return _Section(
      title: 'Practice protocol',
      keyName: 'section-protocol',
      children: [
        _Row('Protocol', '${p.name} · version ${p.version}'),
        _Row('Path', p.path?.label ?? '—'),
        if (summary.assignmentId != null)
          _Row('Assignment', summary.assignmentId!, mono: true),
      ],
    );
  }
}

class _StagesSection extends StatelessWidget {
  const _StagesSection({required this.stages});

  final List<StageRecord> stages;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Stages',
      keyName: 'section-stages',
      children: [
        if (stages.isEmpty)
          const Text('No stage was decided (this path has no stages, or none '
              'was finished).')
        else
          _TableBox(
            keyName: 'stages-table',
            child: DataTable(
              columnSpacing: 20,
              dataRowMinHeight: 36,
              dataRowMaxHeight: 40,
              columns: const [
                DataColumn(label: Text('Stage'), numeric: true),
                DataColumn(label: Text('Decision')),
                DataColumn(label: Text('Reason')),
                DataColumn(label: Text('Correct'), numeric: true),
                DataColumn(label: Text('Unusable'), numeric: true),
                DataColumn(label: Text('Comfort'), numeric: true),
                DataColumn(label: Text('Trials'), numeric: true),
              ],
              rows: [
                for (final s in stages)
                  DataRow(cells: [
                    DataCell(Text('${s.stageIndex + 1}')),
                    DataCell(Text(s.decision)),
                    DataCell(Text(s.reason.isEmpty ? '—' : s.reason)),
                    DataCell(Text(formatPercent(s.correctRatio))),
                    DataCell(Text(formatPercent(s.invalidShare))),
                    DataCell(Text(s.comfortValue == null ? '—' : '${s.comfortValue}')),
                    DataCell(Text('${s.trials}')),
                  ]),
              ],
            ),
          ),
      ],
    );
  }
}

class _TrialsSection extends StatelessWidget {
  const _TrialsSection({required this.trials});

  /// The table shows at most this many rows.
  static const displayLimit = 100;

  final List<TrialRow> trials;

  @override
  Widget build(BuildContext context) {
    final shown = trials.take(displayLimit).toList();
    return _Section(
      title: 'Trials',
      keyName: 'section-trials',
      children: [
        if (trials.isEmpty)
          const Text('No trial was recorded.')
        else ...[
          Text(
            trials.length > displayLimit
                ? 'Showing the first $displayLimit of ${trials.length} trials.'
                : '${trials.length} trials.',
            key: const Key('trials-note'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          _TableBox(
            keyName: 'trials-table',
            maxHeight: 420,
            child: DataTable(
              columnSpacing: 20,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 36,
              headingRowHeight: 38,
              columns: const [
                DataColumn(label: Text('Stage'), numeric: true),
                DataColumn(label: Text('Trial'), numeric: true),
                DataColumn(label: Text('Time')),
                DataColumn(label: Text('Shown')),
                DataColumn(label: Text('Zone')),
                DataColumn(label: Text('Face level'), numeric: true),
                DataColumn(label: Text('Answer')),
                DataColumn(label: Text('Answer time'), numeric: true),
                DataColumn(label: Text('Correct')),
              ],
              rows: [
                for (final t in shown)
                  DataRow(cells: [
                    DataCell(Text('${t.stageIndex + 1}')),
                    DataCell(Text('${t.trialIndex + 1}')),
                    DataCell(Text(formatClockMs(t.tMs))),
                    DataCell(Text(t.numberShown)),
                    DataCell(Text(t.zone)),
                    DataCell(Text(t.faceLevel == null ? '—' : '${t.faceLevel}')),
                    DataCell(Text(t.response ?? 'no answer')),
                    DataCell(Text(t.responseMs == null ? '—' : '${t.responseMs} ms')),
                    DataCell(Text(t.correct == null ? '—' : (t.correct! ? 'Yes' : 'No'))),
                  ]),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _AnswersSection extends StatelessWidget {
  const _AnswersSection({required this.answers});

  final List<AnswerRow> answers;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Answers',
      keyName: 'section-answers',
      children: [
        if (answers.isEmpty)
          const Text('No question was answered.')
        else
          _TableBox(
            keyName: 'answers-table',
            child: DataTable(
              columnSpacing: 20,
              dataRowMinHeight: 36,
              dataRowMaxHeight: 40,
              columns: const [
                DataColumn(label: Text('Time')),
                DataColumn(label: Text('Kind')),
                DataColumn(label: Text('Segment')),
                DataColumn(label: Text('Question')),
                DataColumn(label: Text('Option')),
                DataColumn(label: Text('Correct')),
                DataColumn(label: Text('Next segment')),
              ],
              rows: [
                for (final a in answers)
                  DataRow(cells: [
                    DataCell(Text(formatClockMs(a.tMs))),
                    DataCell(Text(a.kind)),
                    DataCell(Text(a.segmentId)),
                    DataCell(Text(a.questionId)),
                    DataCell(Text(a.option)),
                    DataCell(Text(a.correct == null ? '—' : (a.correct! ? 'Yes' : 'No'))),
                    DataCell(Text(a.nextSegmentId ?? '—')),
                  ]),
              ],
            ),
          ),
      ],
    );
  }
}

class _ComfortAnswersSection extends StatelessWidget {
  const _ComfortAnswersSection({required this.answers, this.comfort});

  final List<ComfortAnswerRow> answers;
  final ComfortConfig? comfort;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Comfort answers',
      keyName: 'section-comfort-answers',
      children: [
        if (answers.isEmpty)
          const Text('No comfort answer was given.')
        else
          for (final a in answers)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      formatClockMs(a.tMs),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontFamilyFallback: kMonospaceFallback,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${a.value}'
                      '${comfort == null ? '' : ' · ${comfort!.labelFor(a.value)}'}'
                      '${a.stageIndex == null ? '' : ' · after stage ${a.stageIndex! + 1}'}'
                      '${a.segment == null ? '' : ' · ${a.segment}'}',
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _DeviceSection extends StatelessWidget {
  const _DeviceSection({required this.detail});

  final SessionDetail detail;

  String _get(Map<String, dynamic> m, String key) => m[key]?.toString() ?? '—';

  @override
  Widget build(BuildContext context) {
    final d = detail.device;
    final cam = detail.camera;
    final g = detail.gazeModel;
    final screen = detail.screen;
    return _Section(
      title: 'Device, screen, camera and gaze model',
      keyName: 'section-device',
      children: [
        _Row('Platform', _get(d, 'platform')),
        _Row('Browser / user agent', _get(d, 'user_agent')),
        if (d['model'] != null) _Row('Device model', _get(d, 'model')),
        _Row(
          'Screen',
          screen == null
              ? '—'
              : '${screen.w.round()} x ${screen.h.round()} px, ${screen.dpr}x pixel ratio',
        ),
        _Row(
          'Camera',
          '${cam['label'] ?? '—'} (${cam['w'] ?? '—'} x ${cam['h'] ?? '—'})',
        ),
        _Row(
          'Gaze model',
          '${_get(g, 'model_id')} ${_get(g, 'model_version')}',
          mono: true,
        ),
        _Row(
          'Development estimator',
          g['synthetic'] == true ? 'Yes (synthetic)' : 'No',
        ),
      ],
    );
  }
}

class _CalibrationSection extends StatelessWidget {
  const _CalibrationSection({required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = summary.calibration;
    return _Section(
      title: 'Calibration',
      keyName: 'section-calibration',
      children: [
        if (c == null)
          const Text('No calibration was run.')
        else ...[
          _Row('Points', '${c.points}'),
          _Row('Median error', '${c.residualPxMedian.toStringAsFixed(1)} px'),
          _Row(
            '90th percentile error',
            c.residualPxP90 == null
                ? '—'
                : '${c.residualPxP90!.toStringAsFixed(1)} px',
          ),
          _Row('Still valid', summary.calibrationValid ? 'Yes' : 'No'),
        ],
      ],
    );
  }
}

class _ValidationSection extends StatelessWidget {
  const _ValidationSection({required this.summary, required this.targets});

  final SessionSummary summary;
  final List<ValidationTargetResult> targets;

  @override
  Widget build(BuildContext context) {
    final v = summary.validation;
    return _Section(
      title: 'Regional validation',
      keyName: 'section-validation',
      children: [
        if (v == null)
          const Text('No validation was run.')
        else ...[
          _Row('Result', v.passed ? 'Passed' : 'Failed'),
          _Row('Correct share', formatPercent(v.correctRatio)),
          _Row('Uncertain share', formatPercent(v.uncertainRatio)),
          _Row('Size ratio', v.sizeRatio.toStringAsFixed(2)),
          if (v.reasons.isNotEmpty) _Row('Reasons', v.reasons.join('\n')),
          if (targets.isNotEmpty) ...[
            const SizedBox(height: 8),
            _TableBox(
              keyName: 'validation-targets',
              child: DataTable(
                columnSpacing: 20,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 40,
                columns: const [
                  DataColumn(label: Text('Target')),
                  DataColumn(label: Text('Position (px)')),
                  DataColumn(label: Text('Samples'), numeric: true),
                  DataColumn(label: Text('Mostly on')),
                  DataColumn(label: Text('Correct')),
                  DataColumn(label: Text('Uncertain'), numeric: true),
                ],
                rows: [
                  for (final t in targets)
                    DataRow(cells: [
                      DataCell(Text(regionLabel(t.region))),
                      DataCell(Text('${t.x.round()}, ${t.y.round()}')),
                      DataCell(Text('${t.n}')),
                      DataCell(Text(regionLabel(t.majority))),
                      DataCell(ValidationBadge(passed: t.correct)),
                      DataCell(Text(formatPercent(t.uncertainShare))),
                    ]),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _CoverageSection extends StatelessWidget {
  const _CoverageSection({required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = summary.coverage;
    final shares = summary.regionShares;
    return _Section(
      title: 'Coverage',
      keyName: 'section-coverage',
      children: [
        _Row('Total', formatDurationMs(c.totalMs)),
        _Row(
          'Classifiable',
          '${formatDurationMs(c.classifiableMs)} (${formatPercent(c.classifiableShare)})',
        ),
        _Row('Uncertain', formatDurationMs(c.uncertainMs)),
        _Row('Missing', formatDurationMs(c.missingMs)),
        if (shares != null) ...[
          _Row('Eyes', formatPercent(shares.eye)),
          _Row('Mouth', formatPercent(shares.mouth)),
          _Row('Rest of the face', formatPercent(shares.faceOther)),
          _Row('Outside the face', formatPercent(shares.outside)),
        ],
        if (summary.notes.isNotEmpty) _Row('Notes', summary.notes.join('\n')),
      ],
    );
  }
}

class _SegmentsSection extends StatelessWidget {
  const _SegmentsSection({required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Segments',
      keyName: 'section-segments',
      children: [
        if (summary.segments.isEmpty)
          const Text('No segment was recorded.')
        else
          _TableBox(
            child: DataTable(
              columnSpacing: 24,
              dataRowMinHeight: 36,
              dataRowMaxHeight: 40,
              columns: const [
                DataColumn(label: Text('Segment')),
                DataColumn(label: Text('Started')),
                DataColumn(label: Text('Ended')),
              ],
              rows: [
                for (final s in summary.segments)
                  DataRow(cells: [
                    DataCell(Text(s.label)),
                    DataCell(Text(formatClockMs(s.startedMs))),
                    DataCell(Text(
                      s.endedMs == null ? 'open' : formatClockMs(s.endedMs!),
                    )),
                  ]),
              ],
            ),
          ),
      ],
    );
  }
}

class _EventsSection extends StatelessWidget {
  const _EventsSection({
    required this.events,
    required this.busy,
    required this.onDownload,
  });

  final List<SessionEventRecord> events;
  final bool busy;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Section(
      title: 'Events timeline',
      keyName: 'section-events',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('download-events-csv'),
              onPressed: busy ? null : onDownload,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('Events CSV'),
            ),
          ),
        ),
        if (events.isEmpty)
          const Text('No events were recorded.')
        else
          for (final e in events)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      formatClockMs(e.tMs),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontFamilyFallback: kMonospaceFallback,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(
                        text: e.type,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (e.payload != null && e.payload!.isNotEmpty)
                        TextSpan(
                          text: '  ${jsonEncode(e.payload)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ])),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _SamplesSection extends StatelessWidget {
  const _SamplesSection({
    required this.controller,
    required this.busy,
    required this.onDownload,
  });

  final SessionDetailController controller;
  final bool busy;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    final total = c.samplesTotal;
    return _Section(
      title: 'Samples',
      keyName: 'section-samples',
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              total == null ? 'Samples: —' : 'Samples: $total',
              key: const Key('samples-count'),
              style: theme.textTheme.bodyLarge,
            ),
            OutlinedButton(
              key: const Key('load-samples'),
              onPressed: c.samplesLoading ? null : c.loadSamples,
              child: Text(c.samplesLoading
                  ? 'Loading...'
                  : (c.samplesLoaded ? 'Reload samples' : 'Load samples')),
            ),
            OutlinedButton.icon(
              key: const Key('download-samples-csv'),
              onPressed: busy ? null : onDownload,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('Samples CSV'),
            ),
          ],
        ),
        if (c.samplesLoaded) ...[
          const SizedBox(height: 8),
          Text(
            c.rows.isEmpty
                ? 'This session has no stored samples.'
                : 'Showing the first ${c.rows.length} of ${c.samplesTotal ?? c.rows.length} samples. '
                    'The Replay button plays them back; Samples CSV has all of them.',
            key: const Key('samples-note'),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (c.rows.isNotEmpty) ...[
            const SizedBox(height: 8),
            _TableBox(
              keyName: 'samples-table',
              maxHeight: 420,
              child: DataTable(
                columnSpacing: 24,
                dataRowMinHeight: 32,
                dataRowMaxHeight: 36,
                headingRowHeight: 38,
                columns: const [
                  DataColumn(label: Text('Time'), numeric: true),
                  DataColumn(label: Text('x'), numeric: true),
                  DataColumn(label: Text('y'), numeric: true),
                  DataColumn(label: Text('Confidence'), numeric: true),
                  DataColumn(label: Text('Valid')),
                  DataColumn(label: Text('Region')),
                  DataColumn(label: Text('Segment')),
                ],
                rows: [
                  for (final r in c.rows)
                    DataRow(cells: [
                      DataCell(Text(formatClockMs(r.tMs))),
                      DataCell(Text(r.x == null ? '—' : r.x!.toStringAsFixed(0))),
                      DataCell(Text(r.y == null ? '—' : r.y!.toStringAsFixed(0))),
                      DataCell(Text(
                        r.conf == null ? '—' : r.conf!.toStringAsFixed(2),
                      )),
                      DataCell(Text(r.valid ? 'Yes' : 'No')),
                      DataCell(Text(regionLabel(r.region))),
                      DataCell(Text(r.segment ?? '—')),
                    ]),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}
