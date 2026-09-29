class Consent {
  const Consent({
    required this.sheetVersion,
    required this.participate,
    this.audioRecording = false,
    this.videoRecording = false,
    this.givenAt,
    this.withdrawnAt,
  });

  final int sheetVersion;
  final bool participate;
  final bool audioRecording;
  final bool videoRecording;
  final String? givenAt;
  final String? withdrawnAt;

  bool get isWithdrawn => withdrawnAt != null;

  /// True when this consent is in force for the given sheet version.
  bool isActiveFor(int currentSheetVersion) =>
      participate && !isWithdrawn && sheetVersion == currentSheetVersion;

  factory Consent.fromJson(Map<String, dynamic> json) => Consent(
        sheetVersion: (json['sheet_version'] as num).toInt(),
        participate: json['participate'] == true,
        audioRecording: json['audio_recording'] == true,
        videoRecording: json['video_recording'] == true,
        givenAt: json['given_at'] as String?,
        withdrawnAt: json['withdrawn_at'] as String?,
      );

  static Consent? maybeFromJson(Object? json) =>
      json is Map<String, dynamic> ? Consent.fromJson(json) : null;
}
