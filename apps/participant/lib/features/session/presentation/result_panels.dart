import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../domain/stimulus_geometry.dart';

/// Card with a coloured heading used by the result panels.
class _ResultHeading extends StatelessWidget {
  const _ResultHeading({
    required this.ok,
    required this.title,
    this.keyName,
  });

  final bool ok;
  final String title;
  final Key? keyName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.error_outline,
          color: ok ? AppColors.success : AppColors.warning,
          size: 26,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            key: keyName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ],
    );
  }
}

class _Reasons extends StatelessWidget {
  const _Reasons({required this.reasons});

  final List<String> reasons;

  @override
  Widget build(BuildContext context) {
    if (reasons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        key: const Key('result-reasons'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Why', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final r in reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(r)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Outcome of the calibration with the residual error in pixels.
class CalibrationResultPanel extends StatelessWidget {
  const CalibrationResultPanel({
    super.key,
    required this.result,
    required this.onContinue,
    required this.onRetry,
  });

  final CalibrationResult result;
  final VoidCallback onContinue;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p90 = result.residualPxP90;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ResultHeading(
              ok: result.accepted,
              title: result.accepted
                  ? 'Calibration accepted'
                  : 'Calibration not accepted',
              keyName: const Key('calibration-title'),
            ),
            const SizedBox(height: 12),
            Text(
              'Typical error: ${result.residualPxMedian.round()} px'
              '${p90 == null ? '' : ' (nine in ten dots within ${p90.round()} px)'}',
              key: const Key('calibration-residual'),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 4),
            Text(
              result.accepted
                  ? 'This is good enough to go on to the validation.'
                  : 'The estimate was not precise enough. Sit still, keep your '
                      'face lit and centred, and try again.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            _Reasons(reasons: result.reasons),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (result.accepted)
                  FilledButton(
                    key: const Key('calibration-continue'),
                    onPressed: onContinue,
                    child: const Text('Continue to validation'),
                  ),
                result.accepted
                    ? OutlinedButton(
                        key: const Key('calibration-retry'),
                        onPressed: onRetry,
                        child: const Text('Calibrate again'),
                      )
                    : FilledButton(
                        key: const Key('calibration-retry'),
                        onPressed: onRetry,
                        child: const Text('Try again'),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Outcome of the regional validation: pass or fail, reasons and the result
/// for each dot.
class ValidationResultPanel extends StatelessWidget {
  const ValidationResultPanel({
    super.key,
    required this.result,
    required this.specs,
    required this.allowContinueWithoutValidation,
    required this.onContinue,
    required this.onRecalibrate,
    required this.onContinueWithout,
    this.cardTooSmall = false,
  });

  final ValidationResult result;
  final List<ValidationTargetSpec> specs;
  final bool allowContinueWithoutValidation;
  final VoidCallback onContinue;
  final VoidCallback onRecalibrate;
  final VoidCallback onContinueWithout;

  /// The face could not be drawn large enough for the calibration error.
  final bool cardTooSmall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <DataRow>[
      for (var i = 0; i < result.targets.length; i++)
        DataRow(cells: [
          DataCell(Text(i < specs.length ? specs[i].label : 'Dot ${i + 1}')),
          DataCell(Text(regionLabel(result.targets[i].region))),
          DataCell(Text(regionLabel(result.targets[i].majority))),
          DataCell(Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                result.targets[i].correct
                    ? Icons.check_circle_outline
                    : Icons.cancel_outlined,
                size: 18,
                color: result.targets[i].correct
                    ? AppColors.success
                    : AppColors.warning,
              ),
              const SizedBox(width: 4),
              Text(result.targets[i].correct ? 'Yes' : 'No'),
            ],
          )),
          DataCell(Text(formatPercent(result.targets[i].uncertainShare))),
        ]),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ResultHeading(
              ok: result.passed,
              title: result.passed ? 'Validation passed' : 'Validation not passed',
              keyName: const Key('validation-title'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                _Metric('On target', formatPercent(result.correctRatio)),
                _Metric('Not sure', formatPercent(result.uncertainRatio)),
                _Metric('Size ratio', result.sizeRatio.toStringAsFixed(1)),
              ],
            ),
            if (cardTooSmall) ...[
              const SizedBox(height: 12),
              const MessageBanner(
                kind: BannerKind.info,
                message:
                    'The window is small for this check. A larger window may help.',
              ),
            ],
            _Reasons(reasons: result.reasons),
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Each dot', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(kRadius),
                ),
                child: SingleChildScrollView(
                  key: const Key('validation-table'),
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 20,
                    dataRowMinHeight: 36,
                    dataRowMaxHeight: 40,
                    headingRowHeight: 38,
                    columns: const [
                      DataColumn(label: Text('Dot')),
                      DataColumn(label: Text('Expected')),
                      DataColumn(label: Text('Mostly on')),
                      DataColumn(label: Text('Correct')),
                      DataColumn(label: Text('Not sure')),
                    ],
                    rows: rows,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (result.passed)
                  FilledButton(
                    key: const Key('validation-continue'),
                    onPressed: onContinue,
                    child: const Text('Continue to baseline'),
                  )
                else ...[
                  FilledButton(
                    key: const Key('validation-recalibrate'),
                    onPressed: onRecalibrate,
                    child: const Text('Recalibrate'),
                  ),
                  if (allowContinueWithoutValidation)
                    OutlinedButton(
                      key: const Key('validation-continue-without'),
                      onPressed: onContinueWithout,
                      child: const Text('Continue without eye-level scoring'),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}
