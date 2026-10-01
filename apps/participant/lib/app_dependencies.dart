import 'package:eyetracking_core/eyetracking_core.dart';

import 'features/assignments/domain/assignments_repository.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/consent/domain/consent_repository.dart';
import 'features/data_export/domain/data_export_repository.dart';
import 'features/debrief/domain/debrief_repository.dart';
import 'features/demographics/domain/demographics_repository.dart';
import 'features/erase/domain/erase_repository.dart';
import 'features/home/domain/home_repository.dart';
import 'features/profile/domain/profile_repository.dart';
import 'features/session/domain/live_repository.dart';
import 'features/session/domain/session_repository.dart';

/// Everything the screens need, expressed as ports so tests can pass fakes.
class AppDependencies {
  const AppDependencies({
    required this.auth,
    required this.home,
    required this.consent,
    required this.profile,
    required this.demographics,
    required this.dataExport,
    required this.sessions,
    required this.gaze,
    required this.frameSource,
    required this.device,
    required this.assignments,
    required this.videoStage,
    required this.erase,
    required this.debrief,
    required this.saveFile,
    required this.live,
    required this.speech,
    required this.audioRecorder,
    this.initialInvitationToken = '',
  });

  final AuthController auth;
  final HomeRepository home;
  final ConsentRepository consent;
  final ProfileRepository profile;
  final DemographicsRepository demographics;
  final DataExportRepository dataExport;
  final SessionRepository sessions;
  final GazeEstimator gaze;
  final FrameSource frameSource;
  final DeviceInfo device;
  final AssignmentsRepository assignments;

  /// Builds the widget that plays a video segment (a `<video>` element in the
  /// browser, a fake in tests).
  final VideoStageBuilder videoStage;

  /// Step 4: withdraw and delete the participant's data.
  final EraseRepository erase;

  /// Step 6: the optional questions after a session.
  final DebriefRepository debrief;

  /// Hands a downloaded file to the browser (a recording fake in tests).
  final FileSaver saveFile;

  /// Step 7: the live conversation's endpoints.
  final LiveRepository live;

  /// Step 7: the avatar's voice (the browser's own; silent in tests).
  final SpeechSynthesizer speech;

  /// Step 7: makes the push-to-talk microphone recorder when it is first
  /// needed.
  final AudioRecorderFactory audioRecorder;

  /// Invitation code taken from the page address, if any.
  final String initialInvitationToken;
}
