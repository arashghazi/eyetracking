import 'dart:async';

import 'package:eyetracking_core/eyetracking_core.dart';

import 'features/access_log/domain/access_log_repository.dart';
import 'features/ai/domain/ai_repository.dart';
import 'features/analysis/domain/analysis_repository.dart';
import 'features/assignments/domain/assignments_repository.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/content/domain/content_repository.dart';
import 'features/content/domain/media_picker.dart';
import 'features/demographics_form/domain/demographics_form_repository.dart';
import 'features/exports/domain/exports_repository.dart';
import 'features/information_sheet/domain/information_sheet_repository.dart';
import 'features/invitations/domain/invitations_repository.dart';
import 'features/measurement_settings/domain/measurement_settings_repository.dart';
import 'features/members/domain/members_repository.dart';
import 'features/participants/domain/participants_repository.dart';
import 'features/protocols/domain/protocols_repository.dart';
import 'features/replay/domain/replay_repository.dart';
import 'features/sessions/domain/sessions_repository.dart';
import 'features/studies/domain/studies_repository.dart';

/// Everything the screens need, expressed as ports so tests can pass fakes.
class AppDependencies {
  const AppDependencies({
    required this.auth,
    required this.studies,
    required this.participants,
    required this.invitations,
    required this.informationSheet,
    required this.demographicsForm,
    required this.members,
    required this.sessions,
    required this.measurementSettings,
    required this.protocols,
    required this.content,
    required this.assignments,
    required this.mediaPicker,
    required this.replay,
    required this.analysis,
    required this.exports,
    required this.accessLog,
    required this.videoStage,
    required this.saveFile,
    required this.ai,
    this.schedule,
  });

  final AuthController auth;
  final StudiesRepository studies;
  final ParticipantsRepository participants;
  final InvitationsRepository invitations;
  final InformationSheetRepository informationSheet;
  final DemographicsFormRepository demographicsForm;
  final MembersRepository members;
  final SessionsRepository sessions;
  final MeasurementSettingsRepository measurementSettings;
  final ProtocolsRepository protocols;
  final ContentRepository content;
  final AssignmentsRepository assignments;

  /// Chooses a file on the researcher's computer (browser file dialog).
  final MediaPicker mediaPicker;

  // Step 4: research and data.
  final ReplayRepository replay;
  final AnalysisRepository analysis;
  final ExportsRepository exports;
  final AccessLogRepository accessLog;

  /// Builds the stimulus video of the replay (a `<video>` element in the
  /// browser, a fake in tests).
  final VideoStageBuilder videoStage;

  /// Hands a downloaded file to the browser (a recording fake in tests).
  final FileSaver saveFile;

  // Step 5: AI content generation.
  final AiRepository ai;

  /// Creates the timer behind the AI tab's auto-refresh; tests pass a fake so
  /// they can fire it by hand. Null uses a real [Timer].
  final Timer Function(Duration, void Function())? schedule;
}
