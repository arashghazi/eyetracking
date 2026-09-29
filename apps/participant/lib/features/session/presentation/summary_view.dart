import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

/// What the participant sees after a session: how much of it could be used,
/// and where attention went. Missing data is never presented as "not looking".
class SummaryView extends StatelessWidget {
  const SummaryView({super.key, required this.summary});

  final SessionSummary summary;

  /// Shown when the estimator was a development stub.
  static const syntheticNote =
      'Development estimator — no measurement claims';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = summary.coverage;
    final eye = summary.eyeRegionAttention;
    final muted = theme.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary.synthetic) ...[
          const MessageBanner(
            key: Key('synthetic-note'),
            kind: BannerKind.info,
            message: syntheticNote,
          ),
          const SizedBox(height: 12),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How much could be used', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Time when the camera could not see you is counted as missing, '
                  'not as looking away.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                const SizedBox(height: 12),
                _CoverageBar(coverage: c),
                const SizedBox(height: 12),
                _Line(
                  'Total',
                  formatDurationMs(c.totalMs),
                  keyName: 'coverage-total',
                ),
                _Line(
                  'Usable',
                  '${formatDurationMs(c.classifiableMs)}'
                      '${c.classifiableShare == null ? '' : ' (${formatPercent(c.classifiableShare)})'}',
                  keyName: 'coverage-classifiable',
                ),
                _Line(
                  'Uncertain',
                  formatDurationMs(c.uncertainMs),
                  keyName: 'coverage-uncertain',
                ),
                _Line(
                  'Missing',
                  formatDurationMs(c.missingMs),
                  keyName: 'coverage-missing',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Where attention went', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                _Line(
                  'Face region',
                  summary.faceRegionShare == null
                      ? 'Not available'
                      : formatPercent(summary.faceRegionShare),
                  keyName: 'face-region-share',
                ),
                _Line(
                  'Eye region',
                  eye.evaluable && eye.share != null
                      ? formatPercent(eye.share)
                      : 'Not evaluable',
                  keyName: 'eye-region-share',
                ),
                if (!(eye.evaluable && eye.share != null) &&
                    eye.reason != null &&
                    eye.reason!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      eye.reason!,
                      key: const Key('eye-region-reason'),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (summary.notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Notes', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  for (final n in summary.notes) Text('•  $n'),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {required this.keyName});

  final String label;
  final String value;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              key: Key(keyName),
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stacked bar: usable, uncertain, missing.
class _CoverageBar extends StatelessWidget {
  const _CoverageBar({required this.coverage});

  final Coverage coverage;

  @override
  Widget build(BuildContext context) {
    final parts = [
      (coverage.classifiableMs, AppColors.teal),
      (coverage.uncertainMs, const Color(0xFFD9A441)),
      (coverage.missingMs, AppColors.border),
    ];
    final total = parts.fold<int>(0, (a, p) => a + p.$1);
    return Semantics(
      label: 'Usable, uncertain and missing time',
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(kRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: total == 0
            ? null
            : Row(
                children: [
                  for (final p in parts)
                    if (p.$1 > 0)
                      Expanded(
                        flex: p.$1,
                        child: ColoredBox(color: p.$2, child: const SizedBox.expand()),
                      ),
                ],
              ),
      ),
    );
  }
}
