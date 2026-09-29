import '../domain/media_picker.dart';

/// Outside the browser there is no file dialog yet.
class PlatformMediaPicker implements MediaPicker {
  @override
  Future<PickedMedia?> pick({String accept = ''}) async => null;
}
