import 'features/auth/application/auth_controller.dart';
import 'features/consent/domain/consent_repository.dart';
import 'features/data_export/domain/data_export_repository.dart';
import 'features/demographics/domain/demographics_repository.dart';
import 'features/home/domain/home_repository.dart';
import 'features/profile/domain/profile_repository.dart';

/// Everything the screens need, expressed as ports so tests can pass fakes.
class AppDependencies {
  const AppDependencies({
    required this.auth,
    required this.home,
    required this.consent,
    required this.profile,
    required this.demographics,
    required this.dataExport,
    this.initialInvitationToken = '',
  });

  final AuthController auth;
  final HomeRepository home;
  final ConsentRepository consent;
  final ProfileRepository profile;
  final DemographicsRepository demographics;
  final DataExportRepository dataExport;

  /// Invitation code taken from the page address, if any.
  final String initialInvitationToken;
}
