import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'app_dependencies.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/assignments/data/api_assignments_repository.dart';
import 'features/auth/data/api_auth_repository.dart';
import 'features/content/data/api_content_repository.dart';
import 'features/content/data/media_picker.dart';
import 'features/demographics_form/data/api_demographics_form_repository.dart';
import 'features/information_sheet/data/api_information_sheet_repository.dart';
import 'features/invitations/data/api_invitations_repository.dart';
import 'features/measurement_settings/data/api_measurement_settings_repository.dart';
import 'features/members/data/api_members_repository.dart';
import 'features/participants/data/api_participants_repository.dart';
import 'features/protocols/data/api_protocols_repository.dart';
import 'features/sessions/data/api_sessions_repository.dart';
import 'features/studies/data/api_studies_repository.dart';

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
    studies: ApiStudiesRepository(api),
    participants: ApiParticipantsRepository(api),
    invitations: ApiInvitationsRepository(api),
    informationSheet: ApiInformationSheetRepository(api),
    demographicsForm: ApiDemographicsFormRepository(api),
    members: ApiMembersRepository(api),
    sessions: ApiSessionsRepository(api),
    measurementSettings: ApiMeasurementSettingsRepository(api),
    protocols: ApiProtocolsRepository(api),
    content: ApiContentRepository(api),
    assignments: ApiAssignmentsRepository(api),
    mediaPicker: PlatformMediaPicker(),
  );
}

Widget bootstrap() => ResearchAdminApp(dependencies: buildDependencies());
