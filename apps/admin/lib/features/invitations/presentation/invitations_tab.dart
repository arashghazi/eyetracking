import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_scope.dart';
import '../application/invitations_controller.dart';
import '../domain/invitation.dart';

class InvitationsTab extends StatefulWidget {
  const InvitationsTab({super.key, required this.studyId});

  final int studyId;

  @override
  State<InvitationsTab> createState() => _InvitationsTabState();
}

class _InvitationsTabState extends State<InvitationsTab>
    with AutomaticKeepAliveClientMixin {
  late final InvitationsController _controller;
  final _email = TextEditingController();
  final _days = TextEditingController(
    text: '${InvitationsController.defaultExpiresDays}',
  );

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = InvitationsController(
      AppScope.read(context).invitations,
      widget.studyId,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _email.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (await _controller.create(email: _email.text, expiresDays: _days.text)) {
      _email.clear();
    }
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    _controller.showNotice('$label copied to the clipboard.');
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
            Text('Invitations', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Each invitation can be used once and creates one participant with '
              'the research code shown below.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('invitee-email'),
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'Invitee email (optional)',
                        helperText:
                            'If set, only this address can accept the invitation.',
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('expires-days'),
                      controller: _days,
                      decoration: const InputDecoration(
                        labelText: 'Days until it expires',
                        helperText:
                            '1 to ${InvitationsController.maxExpiresDays} days.',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _create(),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        key: const Key('create-invitation'),
                        onPressed: c.busy ? null : _create,
                        child: Text(c.busy ? 'Creating...' : 'Create invitation'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (var i = 0; i < c.created.length; i++) ...[
              const SizedBox(height: 12),
              _InvitationCard(
                invitation: c.created[i],
                index: i,
                onCopy: _copy,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.invitation,
    required this.index,
    required this.onCopy,
  });

  final Invitation invitation;
  final int index;
  final void Function(String label, String value) onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              index == 0 ? 'Invitation created' : 'Earlier invitation',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _CopyRow(
              label: 'Research code',
              value: invitation.code,
              copyKey: Key('copy-code-$index'),
              onCopy: () => onCopy('Code', invitation.code),
            ),
            _CopyRow(
              label: 'Invitation token',
              value: invitation.token,
              copyKey: Key('copy-token-$index'),
              onCopy: () => onCopy('Token', invitation.token),
            ),
            const SizedBox(height: 4),
            Text(
              [
                'Expires ${formatTimestamp(invitation.expiresAt)}',
                if (invitation.inviteeEmail != null)
                  'for ${invitation.inviteeEmail}',
              ].join(' '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.label,
    required this.value,
    required this.copyKey,
    required this.onCopy,
  });

  final String label;
  final String value;
  final Key copyKey;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                SelectableText(
                  value,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontFamilyFallback: kMonospaceFallback,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: copyKey,
            onPressed: onCopy,
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy'),
          ),
        ],
      ),
    );
  }
}
