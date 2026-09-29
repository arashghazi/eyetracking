import 'features/auth/application/auth_controller.dart';
import 'features/demographics_form/domain/demographics_form_repository.dart';
import 'features/information_sheet/domain/information_sheet_repository.dart';
import 'features/invitations/domain/invitations_repository.dart';
import 'features/members/domain/members_repository.dart';
import 'features/participants/domain/participants_repository.dart';
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
  });

  final AuthController auth;
  final StudiesRepository studies;
  final ParticipantsRepository participants;
  final InvitationsRepository invitations;
  final InformationSheetRepository informationSheet;
  final DemographicsFormRepository demographicsForm;
  final MembersRepository members;
}
