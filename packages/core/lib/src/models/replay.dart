/// Wire models for the replay bundle of one session (step 4):
/// `GET /studies/{id}/sessions/{sid}/replay`.
///
/// The participant's camera video never exists. A replay is the stimulus
/// geometry plus the gaze estimate; nothing here adds accuracy.
library;

import 'admin_session.dart';
import 'layout.dart';
import 'practice.dart';
import 'quality.dart';
import 'session.dart' show regionLabel;

double? _d(Object? v) => (v as num?)?.toDouble();
int _i(Object? v) => (v as num?)?.toInt() ?? 0;

/// Region codes of a compact sample.
abstract final class ReplayRegion {
  static const eye = 0;
  static const mouth = 1;
  static const faceOther = 2;
  static const outside = 3;
  static const uncertain = 4;

  /// The wire name of a region code (`eye`, `mouth`, ...), or null.
  static String? name(int code) => switch (code) {
        eye => 'eye',
        mouth => 'mouth',
        faceOther => 'face_other',
        outside => 'outside',
        uncertain => 'uncertain',
        _ => null,
      };

  /// Plain-language name of a region code.
  static String label(int code) => regionLabel(name(code));
}

/// One decoded gaze sample. [x] and [y] are null when the estimate was
/// uncertain: such a sample draws nothing.
class ReplaySample {
  const ReplaySample({
    required this.tMs,
    this.x,
    this.y,
    this.conf = 0,
    this.regionCode = ReplayRegion.uncertain,
  });

  final int tMs;
  final double? x;
  final double? y;
  final double conf;
  final int regionCode;

  bool get hasPosition => x != null && y != null;
  String get regionName => ReplayRegion.label(regionCode);

  /// Compact wire row `[t_ms, x, y, conf, region_code]`.
  static ReplaySample fromRow(List<dynamic> row) => ReplaySample(
        tMs: row.isNotEmpty ? _i(row[0]) : 0,
        x: row.length > 1 ? _d(row[1]) : null,
        y: row.length > 2 ? _d(row[2]) : null,
        conf: row.length > 3 ? (_d(row[3]) ?? 0) : 0,
        regionCode: row.length > 4 ? _i(row[4]) : ReplayRegion.uncertain,
      );
}

/// The compact sample rows of a replay. A row is turned into a
/// [ReplaySample] only when it is asked for, so a long session does not
/// create one object per sample up front.
class ReplaySamples {
  ReplaySamples(List<List<dynamic>> rows) : _rows = _sorted(rows);

  const ReplaySamples.empty() : _rows = const [];

  final List<List<dynamic>> _rows;

  static List<List<dynamic>> _sorted(List<List<dynamic>> rows) {
    var ordered = true;
    for (var i = 1; i < rows.length; i++) {
      if (_i(rows[i][0]) < _i(rows[i - 1][0])) {
        ordered = false;
        break;
      }
    }
    if (ordered) return rows;
    return [...rows]..sort((a, b) => _i(a[0]).compareTo(_i(b[0])));
  }

  factory ReplaySamples.fromJson(Object? value) => ReplaySamples([
        if (value is List)
          for (final row in value)
            if (row is List && row.isNotEmpty) row,
      ]);

  int get length => _rows.length;
  bool get isEmpty => _rows.isEmpty;

  /// Decodes row [index].
  ReplaySample operator [](int index) => ReplaySample.fromRow(_rows[index]);

  int tMsAt(int index) => _i(_rows[index][0]);

  int get lastTMs => _rows.isEmpty ? 0 : tMsAt(_rows.length - 1);

  /// Index of the last sample at or before [tMs], or -1 when none.
  int indexAtOrBefore(int tMs) {
    var lo = 0;
    var hi = _rows.length - 1;
    var found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (tMsAt(mid) <= tMs) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  /// The last sample at or before [tMs] that is not older than [maxAgeMs].
  ReplaySample? latestAt(int tMs, {int maxAgeMs = 1000}) {
    final i = indexAtOrBefore(tMs);
    if (i < 0 || tMs - tMsAt(i) > maxAgeMs) return null;
    return this[i];
  }

  /// The samples with `fromMs <= t <= toMs`, oldest first.
  List<ReplaySample> window(int fromMs, int toMs) {
    if (_rows.isEmpty || toMs < fromMs) return const [];
    var i = indexAtOrBefore(fromMs - 1) + 1;
    final out = <ReplaySample>[];
    while (i < _rows.length && tMsAt(i) <= toMs) {
      out.add(this[i]);
      i++;
    }
    return out;
  }
}

/// A stretch of session time, `fromMs` to `toMs`.
class TimeSpan {
  const TimeSpan({required this.fromMs, required this.toMs});

  final int fromMs;
  final int toMs;

  int get lengthMs => toMs - fromMs;
  bool contains(int tMs) => tMs >= fromMs && tMs <= toMs;

  factory TimeSpan.fromJson(Map<String, dynamic> json) =>
      TimeSpan(fromMs: _i(json['from_ms']), toMs: _i(json['to_ms']));
}

/// The valid share of one second (one bar of the quality strip). A null
/// [validShare] means there were no samples in that second (missing).
class QualityStripEntry {
  const QualityStripEntry({
    required this.fromMs,
    required this.toMs,
    this.validShare,
  });

  final int fromMs;
  final int toMs;
  final double? validShare;

  factory QualityStripEntry.fromJson(Map<String, dynamic> json) =>
      QualityStripEntry(
        fromMs: _i(json['from_ms']),
        toMs: _i(json['to_ms']),
        validShare: _d(json['valid_share']),
      );
}

class ReplaySegment {
  const ReplaySegment({
    required this.label,
    required this.startedMs,
    this.endedMs,
  });

  final String label;
  final int startedMs;
  final int? endedMs;

  factory ReplaySegment.fromJson(Map<String, dynamic> json) => ReplaySegment(
        label: json['label']?.toString() ?? '',
        startedMs: _i(json['started_ms']),
        endedMs: (json['ended_ms'] as num?)?.toInt(),
      );
}

/// A stimulus layout with the time it was in use, derived by the server
/// from the samples that were classified against it.
class ReplayLayout {
  const ReplayLayout({
    required this.id,
    required this.segment,
    this.stageIndex,
    required this.layout,
    required this.fromMs,
    required this.toMs,
  });

  final String id;
  final String segment;
  final int? stageIndex;
  final StimulusLayout layout;
  final int fromMs;
  final int toMs;

  bool contains(int tMs) => tMs >= fromMs && tMs <= toMs;

  factory ReplayLayout.fromJson(
    Map<String, dynamic> json, {
    ScreenInfo? fallbackScreen,
  }) {
    final raw = json['layout'];
    final map = raw is Map<String, dynamic> ? raw : const <String, dynamic>{};
    var layout = StimulusLayout.fromJson(map);
    if (map['screen'] is! Map && fallbackScreen != null) {
      layout = StimulusLayout(
        screen: fallbackScreen,
        faceBox: layout.faceBox,
        eyeRegion: layout.eyeRegion,
        mouthRegion: layout.mouthRegion,
      );
    }
    return ReplayLayout(
      id: json['id']?.toString() ?? '',
      segment: json['segment']?.toString() ?? '',
      stageIndex: (json['stage_index'] as num?)?.toInt(),
      layout: layout,
      fromMs: _i(json['from_ms']),
      toMs: _i(json['to_ms']),
    );
  }
}

/// A number (or symbol) shown during practice, with where it was drawn.
class ReplayTrial {
  const ReplayTrial({
    required this.stageIndex,
    required this.trialIndex,
    required this.tMs,
    this.numberShown = '',
    this.zone = '',
    this.x,
    this.y,
    this.faceLevel,
    this.response,
    this.correct,
    this.responseMs,
  });

  final int stageIndex;
  final int trialIndex;
  final int tMs;
  final String numberShown;
  final String zone;

  /// Centre of the number in CSS pixels of the participant's screen.
  final double? x;
  final double? y;
  final int? faceLevel;
  final String? response;
  final bool? correct;
  final int? responseMs;

  bool get hasPosition => x != null && y != null;

  factory ReplayTrial.fromJson(Map<String, dynamic> json) {
    final pos = json['position'];
    double? px;
    double? py;
    if (pos is Map) {
      px = _d(pos['x']);
      py = _d(pos['y']);
    } else if (pos is List && pos.length >= 2) {
      px = _d(pos[0]);
      py = _d(pos[1]);
    }
    return ReplayTrial(
      stageIndex: _i(json['stage_index']),
      trialIndex: _i(json['trial_index']),
      tMs: _i(json['t_ms']),
      numberShown: json['number_shown']?.toString() ?? '',
      zone: json['zone']?.toString() ?? '',
      x: px,
      y: py,
      faceLevel: (json['face_level'] as num?)?.toInt(),
      response: json['response']?.toString(),
      correct: json['correct'] as bool?,
      responseMs: (json['response_ms'] as num?)?.toInt(),
    );
  }
}

/// A stimulus video that started during the session (`media_start` event).
class ReplayMedia {
  const ReplayMedia({
    required this.segmentId,
    required this.mediaKey,
    required this.startMs,
    required this.url,
  });

  final String segmentId;
  final String mediaKey;

  /// Session time at which the clip started.
  final int startMs;

  /// Signed link; use it exactly as given. Empty when the server could not
  /// tell which file the clip was (see [hasUrl]).
  final String url;

  bool get hasUrl => url.isNotEmpty;

  factory ReplayMedia.fromJson(Map<String, dynamic> json) => ReplayMedia(
        segmentId: json['segment_id']?.toString() ?? '',
        mediaKey: json['media_key']?.toString() ?? '',
        startMs: _i(json['start_ms']),
        url: json['url']?.toString() ?? '',
      );
}

class ReplayProtocolInfo {
  const ReplayProtocolInfo({required this.name, this.version = 0, this.path});

  final String name;
  final int version;
  final String? path;

  static ReplayProtocolInfo? maybeFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    return ReplayProtocolInfo(
      name: value['name']?.toString() ?? '',
      version: _i(value['version']),
      path: value['path']?.toString(),
    );
  }
}

class ReplaySession {
  const ReplaySession({
    required this.id,
    required this.participantCode,
    required this.status,
    this.createdAt,
    this.synthetic = false,
    this.quality,
    this.protocol,
  });

  final String id;
  final String participantCode;
  final String status;
  final String? createdAt;
  final bool synthetic;
  final SessionQuality? quality;
  final ReplayProtocolInfo? protocol;

  factory ReplaySession.fromJson(Map<String, dynamic> json) => ReplaySession(
        id: json['id']?.toString() ?? '',
        participantCode: json['participant_code']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        createdAt: json['created_at']?.toString(),
        synthetic: json['synthetic'] == true,
        quality: SessionQuality.maybeFromJson(json['quality']),
        protocol: ReplayProtocolInfo.maybeFromJson(json['protocol']),
      );
}

/// Everything needed to replay one session.
class ReplayBundle {
  ReplayBundle({
    required this.session,
    required this.screen,
    this.segments = const [],
    this.layouts = const [],
    this.samples = const ReplaySamples.empty(),
    this.events = const [],
    this.trials = const [],
    this.answers = const [],
    this.qualityStrip = const [],
    this.gaps = const [],
    this.pauses = const [],
    this.media = const [],
  })  : _media = [...media]..sort((a, b) => a.startMs.compareTo(b.startMs)),
        _trials = [...trials]..sort((a, b) => a.tMs.compareTo(b.tMs));

  /// How long an unanswered trial counts as shown when nothing else says
  /// when it ended.
  static const unansweredTrialMs = 8000;

  final ReplaySession session;
  final ScreenInfo screen;
  final List<ReplaySegment> segments;
  final List<ReplayLayout> layouts;
  final ReplaySamples samples;
  final List<SessionEventRecord> events;
  final List<ReplayTrial> trials;
  final List<AnswerRow> answers;
  final List<QualityStripEntry> qualityStrip;
  final List<TimeSpan> gaps;
  final List<TimeSpan> pauses;
  final List<ReplayMedia> media;

  final List<ReplayMedia> _media;
  final List<ReplayTrial> _trials;

  factory ReplayBundle.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> maps(Object? v) => [
          if (v is List)
            for (final e in v)
              if (e is Map<String, dynamic>) e,
        ];
    final screen = json['screen'] is Map<String, dynamic>
        ? ScreenInfo.fromJson(json['screen'] as Map<String, dynamic>)
        : const ScreenInfo(w: 1280, h: 720);
    return ReplayBundle(
      session: ReplaySession.fromJson(
        json['session'] is Map<String, dynamic>
            ? json['session'] as Map<String, dynamic>
            : const {},
      ),
      screen: screen,
      segments: [for (final m in maps(json['segments'])) ReplaySegment.fromJson(m)],
      layouts: [
        for (final m in maps(json['layouts']))
          ReplayLayout.fromJson(m, fallbackScreen: screen),
      ],
      samples: ReplaySamples.fromJson(json['samples']),
      events: [for (final m in maps(json['events'])) SessionEventRecord.fromJson(m)],
      trials: [for (final m in maps(json['trials'])) ReplayTrial.fromJson(m)],
      answers: [for (final m in maps(json['answers'])) AnswerRow.fromJson(m)],
      qualityStrip: [
        for (final m in maps(json['quality_strip'])) QualityStripEntry.fromJson(m),
      ],
      gaps: [for (final m in maps(json['gaps'])) TimeSpan.fromJson(m)],
      pauses: [for (final m in maps(json['pauses'])) TimeSpan.fromJson(m)],
      media: [for (final m in maps(json['media'])) ReplayMedia.fromJson(m)],
    );
  }

  /// End of the replay: the latest time any part of the bundle mentions.
  late final int durationMs = _computeDuration();

  int _computeDuration() {
    var end = samples.lastTMs;
    for (final s in segments) {
      final e = s.endedMs ?? s.startedMs;
      if (e > end) end = e;
    }
    for (final q in qualityStrip) {
      if (q.toMs > end) end = q.toMs;
    }
    for (final p in pauses) {
      if (p.toMs > end) end = p.toMs;
    }
    for (final e in events) {
      if (e.tMs > end) end = e.tMs;
    }
    return end;
  }

  bool get hasMedia => _media.isNotEmpty;
  List<ReplayMedia> get mediaEntries => _media;
  bool get hasSamples => !samples.isEmpty;

  /// The segment that is open at [tMs], if any.
  ReplaySegment? segmentAt(int tMs) {
    ReplaySegment? found;
    for (final s in segments) {
      final end = s.endedMs ?? durationMs;
      if (tMs >= s.startedMs && tMs <= end) found = s;
    }
    return found;
  }

  /// The layout in use at [tMs]: the one whose samples span that time, or
  /// else the latest layout of the open segment; null outside any segment.
  ReplayLayout? layoutAt(int tMs) {
    ReplayLayout? containing;
    for (final l in layouts) {
      if (l.contains(tMs) && (containing == null || l.fromMs >= containing.fromMs)) {
        containing = l;
      }
    }
    if (containing != null) return containing;
    final segment = segmentAt(tMs);
    if (segment == null) return null;
    ReplayLayout? latest;
    for (final l in layouts) {
      if (l.segment == segment.label &&
          l.fromMs <= tMs &&
          (latest == null || l.fromMs >= latest.fromMs)) {
        latest = l;
      }
    }
    return latest;
  }

  /// When trial [index] (in time order) stopped being shown.
  int trialEndMs(int index) {
    final t = _trials[index];
    if (t.responseMs != null) return t.tMs + t.responseMs!;
    final cap = t.tMs + unansweredTrialMs;
    if (index + 1 < _trials.length) {
      final next = _trials[index + 1].tMs;
      return next < cap ? next : cap;
    }
    return cap;
  }

  /// The trial whose number is on the screen at [tMs], or null.
  ReplayTrial? trialAt(int tMs) {
    for (var i = _trials.length - 1; i >= 0; i--) {
      final t = _trials[i];
      if (t.tMs > tMs) continue;
      return tMs < trialEndMs(i) ? t : null;
    }
    return null;
  }

  TimeSpan? gapAt(int tMs) => _spanAt(gaps, tMs);
  TimeSpan? pauseAt(int tMs) => _spanAt(pauses, tMs);

  static TimeSpan? _spanAt(List<TimeSpan> spans, int tMs) {
    for (final s in spans) {
      if (tMs >= s.fromMs && tMs < s.toMs) return s;
    }
    return null;
  }

  /// When the clip [entry] stopped: the next clip's start, the end of the
  /// segment it started in, or the end of the replay.
  int mediaEndMs(ReplayMedia entry) {
    var end = durationMs;
    final i = _media.indexOf(entry);
    if (i >= 0 && i + 1 < _media.length) {
      end = _media[i + 1].startMs;
    }
    for (final s in segments) {
      final segEnd = s.endedMs;
      if (segEnd != null && entry.startMs >= s.startedMs && entry.startMs < segEnd) {
        if (segEnd < end) end = segEnd;
      }
    }
    return end < entry.startMs ? entry.startMs : end;
  }

  /// The stimulus clip playing at [tMs], or null.
  ReplayMedia? mediaAt(int tMs) {
    for (final m in _media.reversed) {
      if (tMs >= m.startMs) return tMs < mediaEndMs(m) ? m : null;
    }
    return null;
  }

  /// The sample to show at [tMs]: none while the time falls in a gap.
  ReplaySample? sampleAt(int tMs) {
    if (gapAt(tMs) != null) return null;
    return samples.latestAt(tMs);
  }
}
