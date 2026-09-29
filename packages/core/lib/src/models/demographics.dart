enum DemographicsFieldType {
  number('number', 'Number'),
  choice('choice', 'Choice'),
  text('text', 'Text'),
  boolean('boolean', 'Yes / no');

  const DemographicsFieldType(this.wire, this.label);
  final String wire;
  final String label;

  static DemographicsFieldType fromWire(String? value) =>
      DemographicsFieldType.values.firstWhere(
        (t) => t.wire == value,
        orElse: () => DemographicsFieldType.text,
      );
}

class DemographicsField {
  const DemographicsField({
    required this.key,
    required this.label,
    required this.type,
    this.options = const [],
    this.required = false,
  });

  final String key;
  final String label;
  final DemographicsFieldType type;
  final List<String> options;
  final bool required;

  factory DemographicsField.fromJson(Map<String, dynamic> json) =>
      DemographicsField(
        key: json['key'] as String? ?? '',
        label: json['label'] as String? ?? (json['key'] as String? ?? ''),
        type: DemographicsFieldType.fromWire(json['type'] as String?),
        options: [
          for (final o in (json['options'] as List<dynamic>? ?? const []))
            o.toString(),
        ],
        required: json['required'] == true,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type.wire,
        if (type == DemographicsFieldType.choice) 'options': options,
        'required': required,
      };
}

class DemographicsForm {
  const DemographicsForm({required this.version, required this.fields});

  final int version;
  final List<DemographicsField> fields;

  factory DemographicsForm.fromJson(Map<String, dynamic> json) =>
      DemographicsForm(
        version: (json['version'] as num).toInt(),
        fields: [
          for (final f in (json['fields'] as List<dynamic>? ?? const []))
            DemographicsField.fromJson(f as Map<String, dynamic>),
        ],
      );
}

class DemographicsAnswers {
  const DemographicsAnswers({required this.formVersion, required this.answers});

  final int formVersion;
  final Map<String, Object?> answers;

  factory DemographicsAnswers.fromJson(Map<String, dynamic> json) =>
      DemographicsAnswers(
        formVersion: (json['form_version'] as num?)?.toInt() ?? 0,
        answers: Map<String, Object?>.from(
          json['answers'] as Map<String, dynamic>? ?? const {},
        ),
      );

  static DemographicsAnswers? maybeFromJson(Object? json) =>
      json is Map<String, dynamic> ? DemographicsAnswers.fromJson(json) : null;
}
