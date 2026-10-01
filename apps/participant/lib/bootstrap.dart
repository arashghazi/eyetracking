import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'app_dependencies.dart';
import 'features/assignments/data/api_assignments_repository.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/data/api_auth_repository.dart';
import 'features/consent/data/api_consent_repository.dart';
import 'features/data_export/data/api_data_export_repository.dart';
import 'features/debrief/data/api_debrief_repository.dart';
import 'features/demographics/data/api_demographics_repository.dart';
import 'features/erase/data/api_erase_repository.dart';
import 'features/home/data/api_home_repository.dart';
import 'features/profile/data/api_profile_repository.dart';
import 'features/session/data/api_live_repository.dart';
import 'features/session/data/api_session_repository.dart';

/// Service address; override with `--dart-define=API_BASE_URL=...`.
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000',
);

/// Wires the real repositories (HTTP) to the controllers' ports.
AppDependencies buildDependencies({String baseUrl = apiBaseUrl}) {
  late final AuthController auth;
  final api = ApiClient(
    baseUrl: baseUrl,
    onUnauthorized: () => auth.expire(),
  );
  auth = AuthController(ApiAuthRepository(api));
  return AppDependencies(
    auth: auth,
    home: ApiHomeRepository(api),
    consent: ApiConsentRepository(api),
    profile: ApiProfileRepository(api),
    demographics: ApiDemographicsRepository(api),
    dataExport: ApiDataExportRepository(api),
    sessions: ApiSessionRepository(api),
    gaze: GazeServiceClient.fromEnvironment(api),
    frameSource: createFrameSource(),
    device: currentDeviceInfo(),
    assignments: ApiAssignmentsRepository(api),
    videoStage: (context, config) => VideoStage(config: config),
    erase: ApiEraseRepository(api),
    debrief: ApiDebriefRepository(api),
    saveFile: saveFile,
    live: ApiLiveRepository(api),
    speech: createSpeechSynthesizer(),
    audioRecorder: createAudioRecorder,
    initialInvitationToken: Uri.base.queryParameters['invitation'] ?? '',
  );
}

Widget bootstrap() => ParticipantApp(dependencies: buildDependencies());
