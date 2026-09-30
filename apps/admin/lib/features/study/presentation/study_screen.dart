import 'package:flutter/material.dart';

import '../../access_log/presentation/access_log_tab.dart';
import '../../ai/presentation/ai_tab.dart';
import '../../analysis/presentation/analysis_tab.dart';
import '../../demographics_form/presentation/demographics_form_tab.dart';
import '../../information_sheet/presentation/information_sheet_tab.dart';
import '../../invitations/presentation/invitations_tab.dart';
import '../../measurement_settings/presentation/measurement_settings_tab.dart';
import '../../content/presentation/content_tab.dart';
import '../../members/presentation/members_tab.dart';
import '../../participants/presentation/participants_tab.dart';
import '../../protocols/presentation/protocols_tab.dart';
import '../../sessions/presentation/sessions_tab.dart';
import '../../studies/domain/study.dart';

/// One study, split into tabs. The Members tab is for administrators only
/// and the Access log for researchers and administrators.
/// Analysts see the measurement settings, protocols and content read-only.
class StudyScreen extends StatelessWidget {
  const StudyScreen({
    super.key,
    required this.study,
    required this.isAdmin,
    this.canEditSettings = true,
  });

  final Study study;
  final bool isAdmin;
  final bool canEditSettings;

  /// Position of the AI tab (after Content); everything before it is always
  /// shown.
  static const aiTabIndex = 5;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabCount,
      child: Builder(builder: _buildTabs),
    );
  }

  /// Ten tabs everybody sees, plus the Access log (researchers and
  /// administrators) and the Members tab (administrators).
  int get _tabCount =>
      10 + (isAdmin || canEditSettings ? 1 : 0) + (isAdmin ? 1 : 0);

  Widget _buildTabs(BuildContext context) {
    final tabController = DefaultTabController.of(context);
    final tabs = <(String, Widget)>[
      (
        'Participants',
        ParticipantsTab(studyId: study.id, canEdit: canEditSettings),
      ),
      ('Sessions', SessionsTab(studyId: study.id)),
      ('Analysis', AnalysisTab(studyId: study.id)),
      (
        'Protocols',
        ProtocolsTab(studyId: study.id, canEdit: canEditSettings),
      ),
      (
        'Content',
        ContentTab(
          studyId: study.id,
          canEdit: canEditSettings,
          onOpenAiTab: () => tabController.animateTo(aiTabIndex),
        ),
      ),
      (
        'AI',
        AiTab(
          studyId: study.id,
          isAdmin: isAdmin,
          canEdit: canEditSettings,
          tabIndex: aiTabIndex,
        ),
      ),
      ('Invitations', InvitationsTab(studyId: study.id)),
      ('Information sheet', InformationSheetTab(studyId: study.id)),
      ('Demographics form', DemographicsFormTab(studyId: study.id)),
      (
        'Measurement settings',
        MeasurementSettingsTab(studyId: study.id, canEdit: canEditSettings),
      ),
      // Researchers and administrators read the access log; analysts do not.
      if (isAdmin || canEditSettings)
        ('Access log', AccessLogTab(studyId: study.id)),
      if (isAdmin) ('Members', MembersTab(studyId: study.id)),
    ];
    assert(tabs[aiTabIndex].$1 == 'AI' && tabs.length == _tabCount);
    return Scaffold(
      appBar: AppBar(
        title: Text(study.name),
        bottom: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final t in tabs) Tab(text: t.$1)],
        ),
      ),
      body: TabBarView(children: [for (final t in tabs) t.$2]),
    );
  }
}
