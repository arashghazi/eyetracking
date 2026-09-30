/// Reads a decimal number typed by a person: a comma is accepted as the
/// decimal separator. Null when the text is not a finite number.
double? parseDecimal(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  return value == null || !value.isFinite ? null : value;
}

/// Reads a whole number typed by a person; null when it is not one.
int? parseWhole(String text) {
  final value = parseDecimal(text);
  if (value == null || value != value.roundToDouble()) return null;
  return value.round();
}
