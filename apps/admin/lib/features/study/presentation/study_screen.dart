import 'package:flutter/material.dart';

import '../../demographics_form/presentation/demographics_form_tab.dart';
import '../../information_sheet/presentation/information_sheet_tab.dart';
import '../../invitations/presentation/invitations_tab.dart';
import '../../members/presentation/members_tab.dart';
import '../../participants/presentation/participants_tab.dart';
import '../../studies/domain/study.dart';

/// One study, split into tabs. The Members tab is for administrators only.
class StudyScreen extends StatelessWidget {
  const StudyScreen({super.key, required this.study, required this.isAdmin});

  final Study study;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final tabs = <(String, Widget)>[
      ('Participants', ParticipantsTab(studyId: study.id)),
      ('Invitations', InvitationsTab(studyId: study.id)),
      ('Information sheet', InformationSheetTab(studyId: study.id)),
      ('Demographics form', DemographicsFormTab(studyId: study.id)),
      if (isAdmin) ('Members', MembersTab(studyId: study.id)),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(study.name),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final t in tabs) Tab(text: t.$1)],
          ),
        ),
        body: TabBarView(children: [for (final t in tabs) t.$2]),
      ),
    );
  }
}
