/// Per-study thresholds for calibration and regional validation.
class MeasurementSettings {
  const MeasurementSettings({
    this.validationMinCorrect = 0.8,
    this.validationMaxUncertain = 0.2,
    this.minRegionToErrorRatio = 2.0,
    this.gazeConfThreshold = 0.5,
    this.calibrationPoints = 9,
    this.allowContinueWithoutValidation = true,
  });

  static const defaults = MeasurementSettings();

  final double validationMinCorrect;
  final double validationMaxUncertain;
  final double minRegionToErrorRatio;
  final double gazeConfThreshold;
  final int calibrationPoints;
  final bool allowContinueWithoutValidation;

  static const minCalibrationPoints = 5;
  static const maxCalibrationPoints = 16;

  factory MeasurementSettings.fromJson(Map<String, dynamic> json) {
    const d = MeasurementSettings();
    return MeasurementSettings(
      validationMinCorrect: (json['validation_min_correct'] as num?)
              ?.toDouble() ??
          d.validationMinCorrect,
      validationMaxUncertain: (json['validation_max_uncertain'] as num?)
              ?.toDouble() ??
          d.validationMaxUncertain,
      minRegionToErrorRatio: (json['min_region_to_error_ratio'] as num?)
              ?.toDouble() ??
          d.minRegionToErrorRatio,
      gazeConfThreshold:
          (json['gaze_conf_threshold'] as num?)?.toDouble() ??
              d.gazeConfThreshold,
      calibrationPoints:
          (json['calibration_points'] as num?)?.toInt() ?? d.calibrationPoints,
      allowContinueWithoutValidation:
          json['allow_continue_without_validation'] as bool? ??
              d.allowContinueWithoutValidation,
    );
  }

  Map<String, dynamic> toJson() => {
        'validation_min_correct': validationMinCorrect,
        'validation_max_uncertain': validationMaxUncertain,
        'min_region_to_error_ratio': minRegionToErrorRatio,
        'gaze_conf_threshold': gazeConfThreshold,
        'calibration_points': calibrationPoints,
        'allow_continue_without_validation': allowContinueWithoutValidation,
      };

  /// Field errors keyed by wire name; empty when every value is acceptable.
  /// Ratios and the confidence threshold must lie in 0..1, the region-to-error
  /// ratio must be at least 1 and the calibration needs 5..16 points.
  Map<String, String> validate() {
    final errors = <String, String>{};
    void unit(String key, double v) {
      if (v.isNaN || v < 0 || v > 1) errors[key] = 'Enter a value from 0 to 1.';
    }

    unit('validation_min_correct', validationMinCorrect);
    unit('validation_max_uncertain', validationMaxUncertain);
    unit('gaze_conf_threshold', gazeConfThreshold);
    if (minRegionToErrorRatio.isNaN || minRegionToErrorRatio < 1) {
      errors['min_region_to_error_ratio'] = 'Enter a value of 1 or more.';
    }
    if (calibrationPoints < minCalibrationPoints ||
        calibrationPoints > maxCalibrationPoints) {
      errors['calibration_points'] =
          'Enter a whole number from $minCalibrationPoints to $maxCalibrationPoints.';
    }
    return errors;
  }

  @override
  bool operator ==(Object other) =>
      other is MeasurementSettings &&
      other.validationMinCorrect == validationMinCorrect &&
      other.validationMaxUncertain == validationMaxUncertain &&
      other.minRegionToErrorRatio == minRegionToErrorRatio &&
      other.gazeConfThreshold == gazeConfThreshold &&
      other.calibrationPoints == calibrationPoints &&
      other.allowContinueWithoutValidation == allowContinueWithoutValidation;

  @override
  int get hashCode => Object.hash(
        validationMinCorrect,
        validationMaxUncertain,
        minRegionToErrorRatio,
        gazeConfThreshold,
        calibrationPoints,
        allowContinueWithoutValidation,
      );
}
