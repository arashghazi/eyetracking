import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Consent', () {
    test('is active only for the current version and until withdrawn', () {
      const active = Consent(sheetVersion: 3, participate: true);
      expect(active.isActiveFor(3), isTrue);
      expect(active.isActiveFor(4), isFalse);
      const withdrawn = Consent(
        sheetVersion: 3,
        participate: true,
        withdrawnAt: '2026-09-05T08:00:00Z',
      );
      expect(withdrawn.isActiveFor(3), isFalse);
      expect(const Consent(sheetVersion: 3, participate: false).isActiveFor(3), isFalse);
    });

    test('parses the API shape', () {
      final c = Consent.fromJson({
        'sheet_version': 2,
        'participate': true,
        'audio_recording': true,
        'video_recording': false,
        'given_at': '2026-09-01T10:00:00',
        'withdrawn_at': null,
      });
      expect(c.sheetVersion, 2);
      expect(c.audioRecording, isTrue);
      expect(c.videoRecording, isFalse);
      expect(Consent.maybeFromJson(null), isNull);
    });
  });

  group('Profile', () {
    test('round-trips through JSON, sending empty strings to clear fields', () {
      final p = Profile.fromJson({
        'display_name': null,
        'response_mode': 'four_choice',
        'voice_preference': 'calm',
        'face_preference': null,
        'speed': 'slow',
        'accessibility_needs': ['larger text'],
        'interests': ['trains'],
      });
      expect(p.responseMode, ResponseMode.fourChoice);
      expect(p.speed, Speed.slow);
      expect(p.displayName, '');
      final json = p.toJson();
      expect(json['response_mode'], 'four_choice');
      expect(json['display_name'], '');
      expect(json['accessibility_needs'], ['larger text']);
    });

    test('unknown values fall back to defaults', () {
      final p = Profile.fromJson({'response_mode': 'x', 'speed': 'y'});
      expect(p.responseMode, ResponseMode.touch);
      expect(p.speed, Speed.normal);
    });
  });

  group('Demographics', () {
    test('field JSON keeps options only for choice fields', () {
      const choice = DemographicsField(
        key: 'g',
        label: 'Gender',
        type: DemographicsFieldType.choice,
        options: ['a', 'b'],
        required: true,
      );
      expect(choice.toJson(), {
        'key': 'g',
        'label': 'Gender',
        'type': 'choice',
        'options': ['a', 'b'],
        'required': true,
      });
      const text = DemographicsField(
        key: 't',
        label: 'Text',
        type: DemographicsFieldType.text,
        options: ['ignored'],
      );
      expect(text.toJson().containsKey('options'), isFalse);
    });

    test('form parses fields', () {
      final form = DemographicsForm.fromJson({
        'version': 2,
        'fields': [
          {'key': 'age', 'label': 'Age', 'type': 'number', 'required': true},
        ],
      });
      expect(form.version, 2);
      expect(form.fields.single.type, DemographicsFieldType.number);
      expect(form.fields.single.required, isTrue);
    });
  });

  group('ParticipantRecord', () {
    test('derives demographics completeness from readiness reasons', () {
      final incomplete = ParticipantRecord.fromJson({
        'code': 'P-1',
        'readiness': {
          'ready': false,
          'reasons': ['demographics_incomplete'],
        },
        'consent': null,
        'profile': null,
        'demographics': null,
      });
      expect(incomplete.demographicsComplete, isFalse);
      expect(incomplete.consent, isNull);

      final complete = ParticipantRecord.fromJson({
        'code': 'P-2',
        'readiness': {'ready': true, 'reasons': <String>[]},
        'demographics': {'form_version': 1, 'answers': {'age': 30}},
      });
      expect(complete.demographicsComplete, isTrue);
      expect(complete.demographics!.answers['age'], 30);
    });

    test('reason labels are readable', () {
      expect(readinessReasonLabel(ReadinessReason.noInformationSheet),
          'No information sheet published');
      expect(readinessReasonLabel('something_new'), 'something_new');
    });
  });

  group('InformationSheet', () {
    test('parses the five sections and checks completeness', () {
      final sheet = InformationSheet.fromJson({
        'version': 3,
        'aims': 'a',
        'discomfort_sources': 'b',
        'benefits': 'c',
        'data_handling': 'd',
        'stop_rules': 'e',
        'published_at': '2026-09-01T10:00:00Z',
      });
      expect(sheet.version, 3);
      expect(sheet.content.isComplete, isTrue);
      expect(const SheetContent(aims: 'x').isComplete, isFalse);
      expect(sheet.content.toJson().keys, containsAll([
        'aims',
        'discomfort_sources',
        'benefits',
        'data_handling',
        'stop_rules',
      ]));
    });
  });

  test('formatTimestamp handles null and bad input', () {
    expect(formatTimestamp(null), '-');
    expect(formatTimestamp('not a date'), '-');
    // Times are UTC whether or not the server includes the zone marker.
    expect(formatTimestamp('2026-09-01T10:05:00'), '2026-09-01 10:05 UTC');
    expect(formatTimestamp('2026-09-01T10:05:00Z'), '2026-09-01 10:05 UTC');
  });
}
