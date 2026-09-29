import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../application/consent_controller.dart';

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  late final ConsentController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ConsentController(AppScope.read(context).consent)..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmWithdraw() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw consent?'),
        content: const Text(
          'You will no longer be counted as taking part. You can read the '
          'information sheet and give consent again at any time.',
        ),
        actions: [
          TextButton(
            key: const Key('withdraw-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('withdraw-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _controller.withdraw();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Information sheet & consent')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final c = _controller;
          if (c.loading && c.sheet == null && c.error == null) {
            return const Center(child: CircularProgressIndicator());
          }
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
              if (c.sheet == null)
                _NoSheet(onRetry: c.load, failed: c.error != null)
              else ...[
                _SheetView(sheet: c.sheet!),
                const SizedBox(height: 16),
                c.hasActiveConsent
                    ? _ActiveConsent(
                        controller: c,
                        onWithdraw: _confirmWithdraw,
                      )
                    : _ConsentForm(controller: c),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _NoSheet extends StatelessWidget {
  const _NoSheet({required this.onRetry, required this.failed});

  final VoidCallback onRetry;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failed
                  ? 'The information sheet could not be loaded.'
                  : 'There is no information sheet yet.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              failed
                  ? 'Please try again.'
                  : 'The research team has not published it. Please come back later.',
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Reload')),
          ],
        ),
      ),
    );
  }
}

class _SheetView extends StatelessWidget {
  const _SheetView({required this.sheet});

  final InformationSheet sheet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = sheet.content;
    final sections = <(String, String)>[
      ('Aims of the study', content.aims),
      ('Possible sources of discomfort', content.discomfortSources),
      ('Possible benefits', content.benefits),
      ('How your data is handled', content.dataHandling),
      ('Stopping and starting again', content.stopRules),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version ${sheet.version} · published ${formatTimestamp(sheet.publishedAt)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            for (final (heading, text) in sections) ...[
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(heading, style: theme.textTheme.titleMedium),
              ),
              const SizedBox(height: 4),
              SelectableText(text, style: theme.textTheme.bodyLarge),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConsentForm extends StatelessWidget {
  const _ConsentForm({required this.controller});

  final ConsentController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    final consent = c.consent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your choice', style: theme.textTheme.titleMedium),
            if (c.hasStaleConsent) ...[
              const SizedBox(height: 8),
              Text(
                consent!.isWithdrawn
                    ? 'You withdrew your earlier consent. You can give it again below.'
                    : 'The information sheet has changed since you last answered. '
                        'Please read it again and confirm below.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const Key('agree-checkbox'),
              value: c.agree,
              onChanged: c.saving ? null : (v) => c.setAgree(v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('I agree to take part'),
              subtitle: const Text('Required'),
            ),
            CheckboxListTile(
              key: const Key('audio-checkbox'),
              value: c.audio,
              onChanged: c.saving ? null : (v) => c.setAudio(v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow audio recording'),
              subtitle: const Text('Optional'),
            ),
            CheckboxListTile(
              key: const Key('video-checkbox'),
              value: c.video,
              onChanged: c.saving ? null : (v) => c.setVideo(v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow video recording'),
              subtitle: const Text('Optional'),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: const Key('consent-submit'),
                onPressed: c.canSubmit ? c.submit : null,
                child: Text(c.saving ? 'Saving...' : 'Submit consent'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveConsent extends StatelessWidget {
  const _ActiveConsent({required this.controller, required this.onWithdraw});

  final ConsentController controller;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final consent = controller.consent!;
    String yesNo(bool v) => v ? 'allowed' : 'not allowed';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your consent', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 20, color: AppColors.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You agreed to take part on ${formatTimestamp(consent.givenAt)} '
                    '(information sheet version ${consent.sheetVersion}).',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Audio recording: ${yesNo(consent.audioRecording)}'),
            Text('Video recording: ${yesNo(consent.videoRecording)}'),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('withdraw-button'),
              onPressed: controller.saving ? null : onWithdraw,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
              ),
              child: const Text('Withdraw consent'),
            ),
          ],
        ),
      ),
    );
  }
}
