import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

const TextStyle kMono = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: kMonospaceFallback,
);

/// A number for a table cell: `-` when missing, otherwise up to [decimals]
/// decimals without trailing zeros.
String fmtNum(num? v, {int decimals = 3}) {
  if (v == null) return '-';
  if (v == v.roundToDouble()) return v.round().toString();
  var text = v.toStringAsFixed(decimals);
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

/// A signed number with a plus sign for positive values (`+3.2`).
String fmtSigned(num? v, {int decimals = 1}) {
  if (v == null) return '-';
  final text = v.toStringAsFixed(decimals);
  return v > 0 ? '+$text' : text;
}

/// `12 -> 14` for a before/after pair.
String beforeAfter(Object? before, Object? after) => '$before -> $after';

/// A bordered card with a title, an optional caption and a body.
class PilotCard extends StatelessWidget {
  const PilotCard({
    super.key,
    required this.title,
    this.caption,
    this.trailing,
    this.children = const [],
  });

  final String title;
  final String? caption;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                ?trailing,
              ],
            ),
            if (caption != null) ...[
              const SizedBox(height: 4),
              Text(
                caption!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (children.isNotEmpty) const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A small figure with its label, for the summary rows.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.width = 168,
  });

  final String label;
  final String value;
  final String? caption;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.titleMedium),
          if (caption != null)
            Text(
              caption!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// A label and its value, for the live panel.
class FactRow extends StatelessWidget {
  const FactRow({
    super.key,
    required this.label,
    required this.value,
    this.width = 232,
  });

  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// A horizontal share bar with a label and a value text.
class ShareBar extends StatelessWidget {
  const ShareBar({
    super.key,
    required this.label,
    required this.share,
    required this.valueText,
    this.color = AppColors.teal,
  });

  final String label;

  /// 0..1; null draws an empty bar.
  final double? share;
  final String valueText;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = (share ?? 0).clamp(0.0, 1.0);
    return Semantics(
      label: '$label $valueText',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 116,
              child: Text(label, style: theme.textTheme.bodySmall),
            ),
            Expanded(
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.tealTint,
                  border: Border.all(color: AppColors.border),
                ),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(color: color),
                ),
              ),
            ),
            SizedBox(
              width: 76,
              child: Text(
                valueText,
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A prominent warning that must not be missed.
class WarningBox extends StatelessWidget {
  const WarningBox({super.key, required this.title, this.lines = const []});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warningTint,
          border: Border.all(color: AppColors.warning, width: 1.5),
          borderRadius: BorderRadius.circular(kRadius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded,
                size: 22, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: AppColors.warning),
                  ),
                  for (final line in lines)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        line,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.warning),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A bordered table that scrolls sideways when the window is narrower than
/// its columns.
class ScrollTable extends StatelessWidget {
  const ScrollTable({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(kRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: child,
            ),
          ),
        ),
      );
}

/// A research code (never an identity).
class CodeText extends StatelessWidget {
  const CodeText(this.code, {super.key});

  final String code;

  @override
  Widget build(BuildContext context) => Text(
        code,
        style: kMono.copyWith(fontWeight: FontWeight.w600),
      );
}

/// A one-line placeholder card ("nothing here yet").
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(kRadius),
        ),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
}

/// A wide, shallow loading placeholder.
class BusyBox extends StatelessWidget {
  const BusyBox({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
}

/// Sizes a child for a `Wrap` so that on a narrow window it takes the full
/// width and on a wide one at most [width].
class WrapItem extends StatelessWidget {
  const WrapItem({super.key, required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, minWidth: 0),
        child: SizedBox(width: width, child: child),
      );
}

/// The validation verdict of a session in words: `Passed`, `Not passed` or
/// `No validation`.
String verdictText(ValidationVerdict? v) => v == null
    ? 'No validation'
    : (v.passed ? 'Passed' : 'Not passed');
