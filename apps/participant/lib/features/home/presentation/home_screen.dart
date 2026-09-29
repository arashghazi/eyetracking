import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../auth/application/auth_controller.dart';
import '../../consent/presentation/consent_screen.dart';
import '../../data_export/presentation/data_export_screen.dart';
import '../../demographics/presentation/demographics_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../session/application/my_sessions_controller.dart';
import '../../session/presentation/my_sessions_card.dart';
import '../../session/presentation/session_flow_screen.dart';
import '../application/home_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeController _controller;
  late final MySessionsController _sessions;

  @override
  void initState() {
    super.initState();
    final deps = AppScope.read(context);
    _controller = HomeController(deps.home)..load();
    _sessions = MySessionsController(deps.sessions)..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _sessions.dispose();
    super.dispose();
  }

  /// Opens a step and refreshes the checklist when the user comes back.
  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => screen),
    );
    if (mounted) {
      await Future.wait([_controller.load(), _sessions.load()]);
    }
  }

  void _openStep(String id) => switch (id) {
        'consent' => _open(const ConsentScreen()),
        'demographics' => _open(const DemographicsScreen()),
        _ => _open(const ProfileScreen()),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EyeTracking practice'),
        actions: [
          TextButton.icon(
            key: const Key('sign-out'),
            onPressed: widget.auth.signOut,
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign out'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final c = _controller;
          final overview = c.overview;
          return PageFrame(
            banner: c.error != null
                ? MessageBanner(message: c.error!, onDismiss: c.dismissError)
                : null,
            children: [
              if (overview == null)
                c.loading
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton(
                          onPressed: c.load,
                          child: const Text('Try again'),
                        ),
                      )
              else ...[
                _CodeCard(code: overview.code),
                const SizedBox(height: 12),
                _ChecklistCard(controller: c, onOpen: _openStep),
                const SizedBox(height: 12),
                StartSessionCard(
                  enabled: c.isReady,
                  onStart: () => _open(const SessionFlowScreen()),
                ),
                const SizedBox(height: 12),
                ListenableBuilder(
                  listenable: _sessions,
                  builder: (context, _) => MySessionsCard(controller: _sessions),
                ),
                const SizedBox(height: 12),
                const _ReassuranceCard(),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('download-data'),
                    onPressed: () => _open(const DataExportScreen()),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Download my data'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code});

  final String code;

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
              'Your research code',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            SelectableText(
              code,
              key: const Key('research-code'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontFamily: 'monospace',
                fontFamilyFallback: kMonospaceFallback,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'The research team uses this code instead of your name.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({required this.controller, required this.onOpen});

  final HomeController controller;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = controller.checklist;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              controller.isReady
                  ? 'You are ready to start'
                  : 'A few steps are still open',
              key: const Key('readiness-title'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 24),
              _ChecklistRow(item: items[i], onOpen: onOpen),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.item, required this.onOpen});

  final ChecklistItem item;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, statusText) = switch (item.status) {
      StepStatus.done => (Icons.check_circle, AppColors.success, 'Done'),
      StepStatus.todo => (Icons.radio_button_unchecked, AppColors.warning, 'To do'),
      StepStatus.waiting => (Icons.hourglass_empty, AppColors.textMuted, 'Waiting'),
      StepStatus.optional => (Icons.circle_outlined, AppColors.textMuted, 'Optional'),
    };
    final enabled = item.status != StepStatus.waiting;
    final label = switch (item.status) {
      StepStatus.done => 'Review',
      StepStatus.waiting => 'Not available yet',
      _ => 'Open',
    };
    final button = OutlinedButton(
      key: Key('open-${item.id}'),
      onPressed: enabled ? () => onOpen(item.id) : null,
      child: Text(label),
    );

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(
          item.detail,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 480;
        final leading = Semantics(
          label: statusText,
          child: Icon(icon, size: 22, color: color),
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [leading, const SizedBox(width: 10), Expanded(child: text)],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: button,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(child: text),
            const SizedBox(width: 12),
            button,
          ],
        );
      },
    );
  }
}

class _ReassuranceCard extends StatelessWidget {
  const _ReassuranceCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.tealTint,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 20, color: AppColors.tealDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'You can pause or end a session at any time, and come back whenever you like.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.tealDark),
            ),
          ),
        ],
      ),
    );
  }
}
