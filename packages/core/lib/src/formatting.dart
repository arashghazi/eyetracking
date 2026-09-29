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
