import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> statusJson() => {
      'text_provider': {
        'name': 'anthropic',
        'model': 'claude-sonnet',
        'configured': true,
        'synthetic': false,
      },
      'video_provider': {'name': 'fake', 'configured': true, 'synthetic': true},
      'budget': {
        'cost_cap_units': 10,
        'spent_units': 2.5,
        'remaining_units': 7.5,
        'unit': 'usd_estimate',
      },
      'worker': {'enabled': true, 'interval_s': 30},
      'send_free_text': true,
    };

Map<String, dynamic> jobJson() => {
      'id': 12,
      'kind': 'video',
      'status': 'failed',
      'provider': 'fake',
      'content_id': 4,
      'assignment_id': null,
      'segment_id': 's2',
      'attempts': 3,
      'max_attempts': 3,
      'cost_estimate_units': 0.25,
      'cost_actual_units': null,
      'error': 'provider timeout',
      'created_at': '2026-09-29T10:00:00',
      'started_at': '2026-09-29T10:00:05',
      'finished_at': null,
      'request': {'segment_id': 's2'},
      'result': {},
    };

void main() {
  group('AiStatus', () {
    test('reads providers, budget, worker and the free-text setting', () {
      final s = AiStatus.fromJson(statusJson());
      expect(s.textProvider.name, 'anthropic');
      expect(s.textProvider.model, 'claude-sonnet');
      expect(s.textProvider.configured, isTrue);
      expect(s.textProvider.synthetic, isFalse);
      expect(s.videoProvider.model, isNull);
      expect(s.videoProvider.synthetic, isTrue);
      expect(s.budget.costCapUnits, 10);
      expect(s.budget.spentUnits, 2.5);
      expect(s.budget.remainingUnits, 7.5);
      expect(s.budget.unit, 'usd_estimate');
      expect(s.worker.enabled, isTrue);
      expect(s.worker.intervalS, 30);
      expect(s.sendFreeText, isTrue);
    });

    test('missing parts default to not configured and a zero budget', () {
      final s = AiStatus.fromJson(const {});
      expect(s.textProvider.configured, isFalse);
      expect(s.videoProvider.synthetic, isFalse);
      expect(s.budget.costCapUnits, 0);
      expect(s.worker.enabled, isFalse);
      expect(s.sendFreeText, isFalse);
    });

    test('a budget answer may be wrapped and computes the remainder', () {
      final b = AiBudget.fromJson({
        'budget': {'cost_cap_units': 5, 'spent_units': 1}
      });
      expect(b.costCapUnits, 5);
      expect(b.remainingUnits, 4);
    });

    test('copyWith replaces only the budget', () {
      final s = AiStatus.fromJson(statusJson())
          .copyWith(budget: const AiBudget(costCapUnits: 99));
      expect(s.budget.costCapUnits, 99);
      expect(s.textProvider.name, 'anthropic');
    });
  });

  group('AiJob', () {
    test('reads a job with numeric ids as text', () {
      final j = AiJob.fromJson(jobJson());
      expect(j.id, '12');
      expect(j.kind, AiJobKind.video);
      expect(j.status, AiJobStatus.failed);
      expect(j.contentId, '4');
      expect(j.assignmentId, isNull);
      expect(j.segmentId, 's2');
      expect(j.attempts, 3);
      expect(j.costEstimateUnits, 0.25);
      expect(j.costActualUnits, isNull);
      expect(j.error, 'provider timeout');
      expect(j.canRetry, isTrue);
      expect(j.canCancel, isFalse);
      expect(j.isActive, isFalse);
    });

    test('only queued jobs can be cancelled and only failed ones retried', () {
      AiJob with_(String status) => AiJob.fromJson({...jobJson(), 'status': status});
      for (final s in ['queued', 'running', 'succeeded', 'failed', 'cancelled']) {
        expect(with_(s).canCancel, s == 'queued', reason: s);
        expect(with_(s).canRetry, s == 'failed', reason: s);
        expect(with_(s).isActive, s == 'queued' || s == 'running', reason: s);
      }
    });

    test('status labels are plain words', () {
      expect(aiJobStatusLabel('queued'), 'Queued');
      expect(aiJobStatusLabel('cancelled'), 'Cancelled');
      expect(aiJobStatusLabel('odd'), 'odd');
    });
  });

  group('requests', () {
    test('a text job for an assignment sends the id and the shared fields', () {
      final json = const TextJobRequest(
        assignmentId: '7',
        title: ' Trains ',
        faceId: 'f1',
      ).toJson();
      expect(json, {
        'assignment_id': 7,
        'interaction_points': 2,
        'length_seconds': 90,
        'title': 'Trains',
        'face_id': 'f1',
      });
    });

    test('a free-form text job sends topic, name and interests', () {
      final json = const TextJobRequest(
        topic: 'trains',
        displayName: 'Sam',
        interests: ['rail', 'maps'],
        interactionPoints: 0,
        lengthSeconds: 600,
        voiceId: '',
      ).toJson();
      expect(json['topic'], 'trains');
      expect(json['display_name'], 'Sam');
      expect(json['interests'], ['rail', 'maps']);
      expect(json['interaction_points'], 0);
      expect(json['length_seconds'], 600);
      expect(json.containsKey('assignment_id'), isFalse);
      expect(json.containsKey('voice_id'), isFalse);
      expect(json.containsKey('title'), isFalse);
    });

    test('a video job names the content and only the chosen segments', () {
      expect(
        const VideoJobRequest(
          contentId: '4',
          segmentIds: ['s1', 's3'],
          faceId: 'f2',
        ).toJson(),
        {
          'content_id': 4,
          'segment_ids': ['s1', 's3'],
          'face_id': 'f2',
        },
      );
      expect(const VideoJobRequest(contentId: '4').toJson(), {'content_id': 4});
    });

    test('run result', () {
      final r = AiRunResult.fromJson(
          const {'processed': 3, 'succeeded': 2, 'failed': 1});
      expect((r.processed, r.succeeded, r.failed), (3, 2, 1));
    });
  });

  group('content', () {
    test('text_reviewed defaults to false and reads true', () {
      expect(ContentSummary.fromJson(const {'id': 1, 'title': 'A'}).textReviewed,
          isFalse);
      expect(
        ContentSummary.fromJson(
            const {'id': 1, 'title': 'A', 'text_reviewed': true}).textReviewed,
        isTrue,
      );
      expect(
        ContentDetail.fromJson(const {
          'id': 1,
          'title': 'A',
          'text_reviewed': true,
          'definition': {'segments': []},
        }).summary.textReviewed,
        isTrue,
      );
    });
  });

  group('formatUnits', () {
    test('keeps two to four decimals', () {
      expect(formatUnits(0.5), '0.50');
      expect(formatUnits(12), '12.00');
      expect(formatUnits(0.0125), '0.0125');
      expect(formatUnits(1.23456), '1.2346');
      expect(formatUnits(null), '-');
    });
  });
}
