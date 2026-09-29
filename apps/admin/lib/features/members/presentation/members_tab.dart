import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_scope.dart';
import '../application/members_controller.dart';
import '../../studies/presentation/study_settings_card.dart';
import '../domain/members_repository.dart';

/// Administrator tools: add a member to this study and create staff accounts.
class MembersTab extends StatefulWidget {
  const MembersTab({super.key, required this.studyId});

  final int studyId;

  @override
  State<MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<MembersTab>
    with AutomaticKeepAliveClientMixin {
  late final MembersController _controller;
  final _userId = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  StudyRole _studyRole = StudyRole.researcher;
  bool _canLinkIdentity = false;
  StaffRole _staffRole = StaffRole.researcher;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = MembersController(
      AppScope.read(context).members,
      widget.studyId,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _userId.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _addMember() => _controller.addMember(
        userId: _userId.text,
        studyRole: _studyRole,
        canLinkIdentity: _canLinkIdentity,
      );

  Future<void> _createStaff() async {
    final ok = await _controller.createStaff(
      email: _email.text,
      password: _password.text,
      role: _staffRole,
    );
    if (ok) {
      _email.clear();
      _password.clear();
      // The new account's id is what "Add member" needs next.
      final created = _controller.lastCreated;
      if (created != null) _userId.text = '${created.id}';
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        return PageFrame(
          banner: c.error != null
              ? MessageBanner(message: c.error!, onDismiss: c.dismissError)
              : c.notice != null
                  ? MessageBanner(
                      message: c.notice!,
                      kind: BannerKind.success,
                      onDismiss: c.dismissNotice,
                    )
                  : null,
          children: [
            Text('Members', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Administrators decide who can see this study and who may link a '
              'research code to a login email.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            StudySettingsCard(studyId: widget.studyId),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Add a member to this study',
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('member-user-id'),
                      controller: _userId,
                      decoration: const InputDecoration(labelText: 'User id'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<StudyRole>(
                      key: const Key('member-study-role'),
                      initialValue: _studyRole,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Study role'),
                      items: [
                        for (final r in StudyRole.values)
                          DropdownMenuItem(value: r, child: Text(r.label)),
                      ],
                      onChanged: (v) => setState(() => _studyRole = v ?? _studyRole),
                    ),
                    SwitchListTile(
                      key: const Key('member-can-link'),
                      value: _canLinkIdentity,
                      onChanged: (v) => setState(() => _canLinkIdentity = v),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Can link identity'),
                      subtitle: const Text(
                        'May reveal the login email behind a research code.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        key: const Key('add-member'),
                        onPressed: c.busy ? null : _addMember,
                        child: const Text('Add member'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Create staff account', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('staff-email'),
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('staff-password'),
                      controller: _password,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText:
                            'At least ${MembersController.minPasswordLength} characters.',
                      ),
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<StaffRole>(
                      key: const Key('staff-role'),
                      initialValue: _staffRole,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: [
                        for (final r in StaffRole.values)
                          DropdownMenuItem(value: r, child: Text(r.label)),
                      ],
                      onChanged: (v) => setState(() => _staffRole = v ?? _staffRole),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        key: const Key('create-staff'),
                        onPressed: c.busy ? null : _createStaff,
                        child: const Text('Create account'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
