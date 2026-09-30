/// Formats an ISO-8601 timestamp from the API as `yyyy-MM-dd HH:mm UTC`.
///
/// The service stores times in UTC and may omit the zone marker, so values are
/// always read as UTC. Returns [fallback] for null or unparseable input.
String formatTimestamp(String? iso, {String fallback = '-'}) {
  if (iso == null) return fallback;
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return fallback;
  final t = parsed.isUtc
      ? parsed
      : DateTime.utc(
          parsed.year,
          parsed.month,
          parsed.day,
          parsed.hour,
          parsed.minute,
        );
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)} UTC';
}

/// Formats a 0..1 share as a whole percentage such as `43 %`.
String formatPercent(double? share, {String fallback = '—'}) =>
    share == null ? fallback : '${(share * 100).round()} %';

/// Formats a duration in milliseconds as seconds (`12.4 s`) or `m:ss` from a
/// minute on.
String formatDurationMs(int ms) {
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)} s';
  final total = (ms / 1000).round();
  final minutes = total ~/ 60;
  final seconds = (total % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds min';
}

/// Formats a session clock value as `mm:ss.mmm`.
String formatClockMs(int ms) {
  String two(int n) => n.toString().padLeft(2, '0');
  final minutes = ms ~/ 60000;
  final seconds = (ms ~/ 1000) % 60;
  final millis = (ms % 1000).toString().padLeft(3, '0');
  return '${two(minutes)}:${two(seconds)}.$millis';
}

/// Formats a cost in USD-estimate units, at least two and at most four
/// decimals (`0.50`, `0.0125`).
String formatUnits(num? units, {String fallback = '-'}) {
  if (units == null) return fallback;
  var text = units.toStringAsFixed(4);
  while (text.endsWith('0') && text.length - text.indexOf('.') > 3) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}
