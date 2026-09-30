import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../ai/presentation/ai_widgets.dart' show MutedText;
import '../../sessions/presentation/session_widgets.dart'
    show QualityBadge, ValidationBadge;
import '../application/threshold_review_controller.dart';
import 'pilot_widgets.dart';
import 'settings_history_card.dart';

/// Thresholds: try candidate thresholds on the recorded sessions (nothing is
/// saved), read what would change, and as a researcher save them as a new
/// settings version with a rationale. The settings history sits below.
class ThresholdsSection extends StatelessWidget {
  const ThresholdsSection({super.key, required this.controller});

  final ThresholdReviewController controller;

  static const distributionLabels = {
    'correct_ratio': 'Validation: correct share',
    'uncertain_ratio': 'Validation: uncertain share',
    'size_ratio': 'Validation: region-to-error ratio',
    'residual_px_median': 'Calibration residual (px)',
    'uncertain_share': 'Session: uncertain share',
    'missing_share': 'Session: missing share',
  };

  Future<void> _openSaveDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => SaveVersionDialog(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.error != null) ...[
              MessageBanner(
                key: const Key('threshold-error'),
                message: c.error!,
                onDismiss: c.dismissError,
              ),
              const SizedBox(height: 12),
            ] else if (c.notice != null) ...[
              MessageBanner(
                key: const Key('threshold-notice'),
                kind: BannerKind.success,
                message: c.notice!,
                onDismiss: c.dismissNotice,
              ),
              const SizedBox(height: 12),
            ],
            if (c.current == null)
              c.loading
                  ? const BusyBox()
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        key: const Key('threshold-retry'),
                        onPressed: c.load,
                        child: const Text('Try again'),
                      ),
                    )
            else ...[
              _CurrentCard(controller: c),
              const SizedBox(height: 12),
              _CandidateCard(
                controller: c,
                onSave: () => _openSaveDialog(context),
              ),
              if (c.review != null) ...[
                const SizedBox(height: 12),
                _ReviewResults(controller: c),
              ],
            ],
            const SizedBox(height: 12),
            SettingsHistoryCard(controller: c.history),
          ],
        );
      },
    );
  }
}

class _CurrentCard extends StatelessWidget {
  const _CurrentCard({required this.controller});

  final ThresholdReviewController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.current!;
    final values = SettingsValues(
      validationMinCorrect: s.validationMinCorrect,
      validationMaxUncertain: s.validationMaxUncertain,
      minRegionToErrorRatio: s.minRegionToErrorRatio,
      gazeConfThreshold: s.gazeConfThreshold,
      calibrationPoints: s.calibrationPoints,
      allowContinueWithoutValidation: s.allowContinueWithoutValidation,
      qualityMaxUncertainShare: s.qualityMaxUncertainShare,
      qualityMaxMissingShare: s.qualityMaxMissingShare,
    );
    return PilotCard(
      title: 'Current settings',
      trailing: Text(
        'Version ${s.version}',
        key: const Key('threshold-version'),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      caption: 'The thresholds new validations and quality grades use now.',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final key in SettingsValues.keys)
              StatTile(
                key: Key('current-$key'),
                label: settingLabel(key),
                value: formatSettingValue(values[key]),
                width: 190,
              ),
          ],
        ),
      ],
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.controller, required this.onSave});

  final ThresholdReviewController controller;
  final VoidCallback onSave;

  String _saveHint(ThresholdReviewController c) {
    if (c.review == null) return 'Review the values first.';
    if (c.stale) return 'The values changed after the review; review again.';
    if (c.reviewedChanges.isEmpty) return 'No value differs from the current settings.';
    return 'Saves ${c.reviewedChanges.length} changed '
        '${c.reviewedChanges.length == 1 ? 'value' : 'values'} as version ${c.version + 1}.';
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return PilotCard(
      title: 'Candidate thresholds',
      caption: 'Try other thresholds on the sessions recorded so far. Nothing '
          'is saved until a researcher saves a new settings version.',
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            for (final f in ThresholdReviewController.fields)
              WrapItem(
                width: 240,
                child: KeyedSubtree(
                  key: ValueKey('candidate-${f.key}-${c.epoch}'),
                  child: TextFormField(
                    key: Key('candidate-${f.key}'),
                    initialValue: c.text(f.key),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: f.label,
                      helperText: 'Now ${c.currentText(f.key)}. ${f.help}',
                      helperMaxLines: 3,
                      errorText: c.errorFor(f.key),
                      errorMaxLines: 2,
                    ),
                    onChanged: (v) => c.setText(f.key, v),
                    onFieldSubmitted: (_) => c.runReview(),
                  ),
                ),
              ),
          ],
        ),
        SwitchListTile(
          key: const Key('threshold-include-synthetic'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Include synthetic sessions'),
          subtitle: const Text(
            'Sessions from the development estimator mean nothing for '
            'measurement. They are left out unless you include them.',
          ),
          value: c.includeSynthetic,
          onChanged: c.reviewing ? null : c.setIncludeSynthetic,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              key: const Key('threshold-review'),
              onPressed: c.reviewing ? null : c.runReview,
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: Text(c.reviewing ? 'Reviewing...' : 'Review'),
            ),
            OutlinedButton(
              key: const Key('threshold-reset'),
              onPressed: c.reviewing ? null : c.resetCandidates,
              child: const Text('Reset values'),
            ),
            if (c.canEdit)
              OutlinedButton.icon(
                key: const Key('threshold-save'),
                onPressed: c.canSave ? onSave : null,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save as new settings version'),
              ),
          ],
        ),
        if (c.canEdit) ...[
          const SizedBox(height: 6),
          MutedText(_saveHint(c)),
        ] else ...[
          const SizedBox(height: 6),
          const MutedText(
            'You have read-only access. Researchers of this study can save a '
            'new settings version.',
          ),
        ],
      ],
    );
  }
}

class _ReviewResults extends StatelessWidget {
  const _ReviewResults({required this.controller});

  final ThresholdReviewController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final r = c.review!;
    final theme = Theme.of(context);
    return PilotCard(
      key: const Key('threshold-results'),
      title: 'What the candidate would change',
      caption: 'Version ${r.current.version} today. '
          '${r.sessions} ${r.sessions == 1 ? 'session' : 'sessions'} reviewed'
          '${r.includesSynthetic ? ', synthetic ones included' : r.skippedSynthetic > 0 ? ', ${r.skippedSynthetic} synthetic left out' : ''}.',
      children: [
        if (c.stale) ...[
          const MessageBanner(
            key: Key('threshold-stale'),
            kind: BannerKind.info,
            message: 'The candidate values changed after this review. Review '
                'again before saving.',
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatTile(
              key: const Key('review-validation'),
              label: 'Validation passed',
              value: beforeAfter(r.validationPass.current, r.validationPass.candidate),
              caption: 'of ${r.validatedSessions} validated, now -> candidate',
              width: 200,
            ),
            for (final grade in QualityGrade.all)
              StatTile(
                key: Key('review-quality-$grade'),
                label: 'Quality ${qualityGradeLabel(grade)}',
                value: beforeAfter(
                  r.qualityCurrent.count(grade),
                  r.qualityCandidate.count(grade),
                ),
                caption: 'sessions, now -> candidate',
                width: 200,
              ),
            StatTile(
              key: const Key('review-changed'),
              label: 'Sessions that change',
              value: '${r.changedSessions}',
              caption: 'verdict or grade differs',
              width: 200,
            ),
          ],
        ),
        if (r.notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Column(
            key: const Key('review-notes'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final note in r.notes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2, right: 6),
                        child: Icon(Icons.info_outline, size: 16),
                      ),
                      Expanded(child: Text(note, style: theme.textTheme.bodyMedium)),
                    ],
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Text('Distributions', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        const MutedText('Over the reviewed sessions that have the metric.'),
        const SizedBox(height: 8),
        _DistributionTable(review: r),
        const SizedBox(height: 16),
        Text('By device', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _DeviceTable(review: r),
        const SizedBox(height: 16),
        Text('Sessions', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        const MutedText('Rows that change are highlighted.'),
        const SizedBox(height: 8),
        _RowsTable(review: r),
      ],
    );
  }
}

class _DistributionTable extends StatelessWidget {
  const _DistributionTable({required this.review});

  final ThresholdReview review;

  @override
  Widget build(BuildContext context) {
    final keys = [
      for (final k in ThresholdReview.distributionKeys)
        if (review.distributions.containsKey(k)) k,
      for (final k in review.distributions.keys)
        if (!ThresholdReview.distributionKeys.contains(k)) k,
    ];
    return ScrollTable(
      child: DataTable(
        key: const Key('review-distributions'),
        columnSpacing: 20,
        columns: const [
          DataColumn(label: Text('Metric')),
          DataColumn(label: Text('n'), numeric: true),
          DataColumn(label: Text('Min'), numeric: true),
          DataColumn(label: Text('p25'), numeric: true),
          DataColumn(label: Text('Median'), numeric: true),
          DataColumn(label: Text('p75'), numeric: true),
          DataColumn(label: Text('p90'), numeric: true),
          DataColumn(label: Text('Max'), numeric: true),
        ],
        rows: [
          for (final k in keys)
            DataRow(
              key: ValueKey('dist-$k'),
              cells: [
                DataCell(Text(ThresholdsSection.distributionLabels[k] ?? k)),
                DataCell(Text('${review.distributions[k]!.n}')),
                DataCell(Text(fmtNum(review.distributions[k]!.min))),
                DataCell(Text(fmtNum(review.distributions[k]!.p25))),
                DataCell(Text(fmtNum(review.distributions[k]!.median))),
                DataCell(Text(fmtNum(review.distributions[k]!.p75))),
                DataCell(Text(fmtNum(review.distributions[k]!.p90))),
                DataCell(Text(fmtNum(review.distributions[k]!.max))),
              ],
            ),
        ],
      ),
    );
  }
}

class _DeviceTable extends StatelessWidget {
  const _DeviceTable({required this.review});

  final ThresholdReview review;

  @override
  Widget build(BuildContext context) {
    if (review.byDevice.isEmpty) return const EmptyNote('No sessions to group.');
    return ScrollTable(
      child: DataTable(
        key: const Key('review-devices'),
        columnSpacing: 24,
        columns: const [
          DataColumn(label: Text('Device')),
          DataColumn(label: Text('Sessions'), numeric: true),
          DataColumn(label: Text('Validated'), numeric: true),
          DataColumn(label: Text('Passed now'), numeric: true),
          DataColumn(label: Text('Passed candidate'), numeric: true),
        ],
        rows: [
          for (final d in review.byDevice)
            DataRow(
              key: ValueKey('device-${d.devicePlatform}'),
              cells: [
                DataCell(Text(d.devicePlatform)),
                DataCell(Text('${d.sessions}')),
                DataCell(Text('${d.validated}')),
                DataCell(Text('${d.passCurrent}')),
                DataCell(Text('${d.passCandidate}')),
              ],
            ),
        ],
      ),
    );
  }
}

class _RowsTable extends StatelessWidget {
  const _RowsTable({required this.review});

  final ThresholdReview review;

  Widget _verdict(ValidationVerdict? now, ValidationVerdict? candidate) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValidationBadge(passed: now?.passed),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward, size: 14),
          ),
          ValidationBadge(passed: candidate?.passed),
        ],
      );

  Widget _quality(SessionQuality? now, SessionQuality? candidate) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          QualityBadge(quality: now),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward, size: 14),
          ),
          QualityBadge(quality: candidate),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (review.rows.isEmpty) {
      return const EmptyNote('No sessions to review yet.');
    }
    return ScrollTable(
      child: DataTable(
        key: const Key('review-rows'),
        columnSpacing: 18,
        dataRowMinHeight: 44,
        dataRowMaxHeight: 60,
        columns: const [
          DataColumn(label: Text('Participant')),
          DataColumn(label: Text('Created')),
          DataColumn(label: Text('Device')),
          DataColumn(label: Text('Settings v'), numeric: true),
          DataColumn(label: Text('Validation now -> candidate')),
          DataColumn(label: Text('Quality now -> candidate')),
          DataColumn(label: Text('Correct'), numeric: true),
          DataColumn(label: Text('Uncertain'), numeric: true),
          DataColumn(label: Text('Ratio'), numeric: true),
          DataColumn(label: Text('Residual px'), numeric: true),
          DataColumn(label: Text('Changed')),
        ],
        rows: [
          for (final r in review.rows)
            DataRow(
              key: ValueKey('review-row-${r.sessionId}'),
              color: r.changed
                  ? const WidgetStatePropertyAll(AppColors.warningTint)
                  : null,
              cells: [
                DataCell(Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CodeText(r.participantCode),
                    if (r.synthetic)
                      Text('synthetic',
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                )),
                DataCell(Text(formatTimestamp(r.createdAt))),
                DataCell(Text(r.devicePlatform ?? '-')),
                DataCell(Text(r.settingsVersion == null ? '-' : '${r.settingsVersion}')),
                DataCell(_verdict(r.validationCurrent, r.validationCandidate)),
                DataCell(_quality(r.qualityCurrent, r.qualityCandidate)),
                DataCell(Text(fmtNum(r.metrics.correctRatio))),
                DataCell(Text(fmtNum(r.metrics.uncertainRatio))),
                DataCell(Text(fmtNum(r.metrics.sizeRatio))),
                DataCell(Text(fmtNum(r.metrics.residualPxMedian))),
                DataCell(Text(r.changed ? 'Changed' : 'Same',
                    style: TextStyle(
                      fontWeight: r.changed ? FontWeight.w600 : FontWeight.w400,
                    ))),
              ],
            ),
        ],
      ),
    );
  }
}

/// The dialog behind "Save as new settings version": shows the changes and
/// asks for the rationale (at least 10 characters).
class SaveVersionDialog extends StatefulWidget {
  const SaveVersionDialog({super.key, required this.controller});

  final ThresholdReviewController controller;

  @override
  State<SaveVersionDialog> createState() => _SaveVersionDialogState();
}

class _SaveVersionDialogState extends State<SaveVersionDialog> {
  final _rationale = TextEditingController();

  @override
  void dispose() {
    _rationale.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final ok = await widget.controller.saveAsVersion(_rationale.text);
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([c, _rationale]),
      builder: (context, _) {
        final length = _rationale.text.trim().length;
        final enough = length >= ThresholdReviewController.minRationaleChars;
        final changes = c.pendingChanges;
        return AlertDialog(
          key: const Key('save-version-dialog'),
          title: Text('Save as settings version ${c.version + 1}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'These values change. New validations use the new '
                    'version; sessions already recorded keep the version they '
                    'were validated with.',
                  ),
                  const SizedBox(height: 12),
                  for (final ch in changes)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '${ch.label}: ${ch.text}',
                        key: Key('save-change-${ch.key}'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('rationale-field'),
                    controller: _rationale,
                    autofocus: true,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: ThresholdReviewController.maxRationaleChars,
                    decoration: InputDecoration(
                      labelText: 'Rationale (at least '
                          '${ThresholdReviewController.minRationaleChars} characters)',
                      helperText: 'Why these values? Kept with the version and '
                          'your account.',
                      helperMaxLines: 2,
                    ),
                    onChanged: (_) => c.clearSaveError(),
                  ),
                  if (c.saveError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: MessageBanner(
                        key: const Key('save-version-error'),
                        message: c.saveError!,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              key: const Key('save-version-cancel'),
              onPressed: c.saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('save-version-confirm'),
              onPressed: enough && !c.saving ? _confirm : null,
              child: Text(c.saving ? 'Saving...' : 'Save version'),
            ),
          ],
        );
      },
    );
  }
}
