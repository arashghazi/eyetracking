import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../assignments/presentation/assignments_section.dart';
import '../application/participants_controller.dart';
import 'yes_no.dart';

class ParticipantDetailScreen extends StatefulWidget {
  const ParticipantDetailScreen({
    super.key,
    required this.studyId,
    required this.initial,
    this.canEdit = true,
  });

  final int studyId;
  final ParticipantRecord initial;

  /// Researchers may assign protocols and attach content.
  final bool canEdit;

  @override
  State<ParticipantDetailScreen> createState() =>
      _ParticipantDetailScreenState();
}

class _ParticipantDetailScreenState extends State<ParticipantDetailScreen> {
  late final ParticipantDetailController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ParticipantDetailController(
      AppScope.read(context).participants,
      widget.studyId,
      widget.initial,
    );
    _controller.refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Participant ${widget.initial.code}')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final c = _controller;
          final r = c.record;
          return PageFrame(
            banner: c.error != null
                ? MessageBanner(message: c.error!, onDismiss: c.dismissError)
                : null,
            children: [
              _Section(
                title: 'Readiness',
                children: [
                  _Row('Research code', r.code, mono: true),
                  _RowWidget('Ready', YesNo(value: r.readiness.ready)),
                  _Row(
                    'Reasons',
                    r.readiness.reasons.isEmpty
                        ? '-'
                        : r.readiness.reasons.map(readinessReasonLabel).join('\n'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Section(title: 'Consent', children: _consentRows(r.consent)),
              const SizedBox(height: 12),
              _Section(title: 'Profile', children: _profileRows(r.profile)),
              const SizedBox(height: 12),
              _Section(
                title: 'Demographics',
                children: _demographicsRows(r),
              ),
              const SizedBox(height: 12),
              AssignmentsSection(
                studyId: widget.studyId,
                code: r.code,
                canEdit: widget.canEdit,
              ),
              const SizedBox(height: 12),
              _IdentityCard(controller: c),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _consentRows(Consent? consent) {
    if (consent == null) return const [_Row('Status', 'No consent recorded')];
    return [
      _Row(
        'Status',
        consent.isWithdrawn ? 'Withdrawn' : (consent.participate ? 'Agreed' : 'Declined'),
      ),
      _Row('Sheet version', '${consent.sheetVersion}'),
      _Row('Given', formatTimestamp(consent.givenAt)),
      if (consent.isWithdrawn)
        _Row('Withdrawn', formatTimestamp(consent.withdrawnAt)),
      _Row('Audio recording', consent.audioRecording ? 'Allowed' : 'Not allowed'),
      _Row('Video recording', consent.videoRecording ? 'Allowed' : 'Not allowed'),
    ];
  }

  List<Widget> _profileRows(Profile? p) {
    if (p == null) return const [_Row('Status', 'No profile saved')];
    String orDash(String s) => s.isEmpty ? '-' : s;
    String list(List<String> l) => l.isEmpty ? '-' : l.join(', ');
    return [
      _Row('Display name', orDash(p.displayName)),
      _Row('Response mode', p.responseMode.label),
      _Row('Voice preference', orDash(p.voicePreference)),
      _Row('Face preference', orDash(p.facePreference)),
      _Row('Speed', p.speed.label),
      _Row('Accessibility needs', list(p.accessibilityNeeds)),
      _Row('Interests', list(p.interests)),
    ];
  }

  List<Widget> _demographicsRows(ParticipantRecord r) {
    final d = r.demographics;
    return [
      _RowWidget('Complete', YesNo(value: r.demographicsComplete)),
      if (d == null)
        const _Row('Answers', 'No answers saved')
      else ...[
        _Row('Form version', '${d.formVersion}'),
        for (final e in d.answers.entries) _Row(e.key, '${e.value}'),
      ],
    ];
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A label with a value that wraps under it on narrow screens.
class _RowWidget extends StatelessWidget {
  const _RowWidget(this.label, this.value);

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(builder: (context, constraints) {
        final labelText = Text(
          label,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        );
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [labelText, value],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 180, child: labelText),
            Expanded(child: Align(alignment: Alignment.centerLeft, child: value)),
          ],
        );
      }),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return _RowWidget(
      label,
      SelectableText(
        value,
        style: mono
            ? const TextStyle(
                fontFamily: 'monospace',
                fontFamilyFallback: kMonospaceFallback,
              )
            : null,
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.controller});

  final ParticipantDetailController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Identity', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'The login email is hidden. Revealing it needs the identity-link '
              'permission for this study.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (c.identityMessage != null) ...[
              MessageBanner(message: c.identityMessage!),
              const SizedBox(height: 12),
            ],
            if (c.identityEmail != null) ...[
              Row(
                children: [
                  const Icon(Icons.mail_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      c.identityEmail!,
                      key: const Key('identity-email'),
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('hide-identity'),
                onPressed: c.hideIdentity,
                child: const Text('Hide identity'),
              ),
            ] else
              OutlinedButton(
                key: const Key('reveal-identity'),
                onPressed: c.revealing ? null : c.revealIdentity,
                child: Text(c.revealing ? 'Checking...' : 'Reveal identity'),
              ),
          ],
        ),
      ),
    );
  }
}
