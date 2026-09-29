/// The participant's own raw data (`GET /me/data`), reduced to the counts
/// the download screen shows. The full object is what gets downloaded.
library;

class MyDataCounts {
  const MyDataCounts({
    this.sessions = 0,
    this.samples = 0,
    this.events = 0,
    this.consents = 0,
  });

  final int sessions;

  /// Gaze samples over all sessions.
  final int samples;
  final int events;
  final int consents;

  /// Counts what `/me/data` contains: `sessions[].samples`, `sessions[].events`
  /// and `consents`.
  factory MyDataCounts.fromJson(Object? data) {
    if (data is! Map) return const MyDataCounts();
    int len(Object? v) => v is List ? v.length : 0;
    var samples = 0;
    var events = 0;
    final sessions = data['sessions'];
    if (sessions is List) {
      for (final s in sessions) {
        if (s is Map) {
          samples += len(s['samples']);
          events += len(s['events']);
        }
      }
    }
    return MyDataCounts(
      sessions: len(sessions),
      samples: samples,
      events: events,
      consents: len(data['consents']),
    );
  }
}
