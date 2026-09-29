enum ResponseMode {
  keyboard('keyboard', 'Keyboard'),
  touch('touch', 'Touch'),
  fourChoice('four_choice', 'Four choices'),
  symbol('symbol', 'Symbols');

  const ResponseMode(this.wire, this.label);
  final String wire;
  final String label;

  static ResponseMode fromWire(String? value) => ResponseMode.values.firstWhere(
        (m) => m.wire == value,
        orElse: () => ResponseMode.touch,
      );
}

enum Speed {
  slow('slow', 'Slow'),
  normal('normal', 'Normal'),
  fast('fast', 'Fast');

  const Speed(this.wire, this.label);
  final String wire;
  final String label;

  static Speed fromWire(String? value) => Speed.values.firstWhere(
        (s) => s.wire == value,
        orElse: () => Speed.normal,
      );
}

class Profile {
  const Profile({
    this.displayName = '',
    this.responseMode = ResponseMode.touch,
    this.voicePreference = '',
    this.facePreference = '',
    this.speed = Speed.normal,
    this.accessibilityNeeds = const [],
    this.interests = const [],
  });

  final String displayName;
  final ResponseMode responseMode;
  final String voicePreference;
  final String facePreference;
  final Speed speed;
  final List<String> accessibilityNeeds;
  final List<String> interests;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        displayName: json['display_name'] as String? ?? '',
        responseMode: ResponseMode.fromWire(json['response_mode'] as String?),
        voicePreference: json['voice_preference'] as String? ?? '',
        facePreference: json['face_preference'] as String? ?? '',
        speed: Speed.fromWire(json['speed'] as String?),
        accessibilityNeeds: _strings(json['accessibility_needs']),
        interests: _strings(json['interests']),
      );

  Map<String, dynamic> toJson() => {
        // Empty strings (not null) so that clearing a field is saved: the
        // server ignores nulls as "no change".
        'display_name': displayName.trim(),
        'response_mode': responseMode.wire,
        'voice_preference': voicePreference.trim(),
        'face_preference': facePreference.trim(),
        'speed': speed.wire,
        'accessibility_needs': accessibilityNeeds,
        'interests': interests,
      };

  Profile copyWith({
    String? displayName,
    ResponseMode? responseMode,
    String? voicePreference,
    String? facePreference,
    Speed? speed,
    List<String>? accessibilityNeeds,
    List<String>? interests,
  }) =>
      Profile(
        displayName: displayName ?? this.displayName,
        responseMode: responseMode ?? this.responseMode,
        voicePreference: voicePreference ?? this.voicePreference,
        facePreference: facePreference ?? this.facePreference,
        speed: speed ?? this.speed,
        accessibilityNeeds: accessibilityNeeds ?? this.accessibilityNeeds,
        interests: interests ?? this.interests,
      );

  static List<String> _strings(Object? value) => [
        for (final v in (value as List<dynamic>? ?? const [])) v.toString(),
      ];
}
