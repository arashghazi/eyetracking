import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../auth/application/auth_controller.dart';
import '../../study/presentation/study_screen.dart';
import '../application/studies_controller.dart';

class StudiesScreen extends StatefulWidget {
  const StudiesScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<StudiesScreen> createState() => _StudiesScreenState();
}

class _StudiesScreenState extends State<StudiesScreen> {
  late final StudiesController _controller;
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = StudiesController(AppScope.read(context).studies);
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (await _controller.create(_name.text)) _name.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = widget.auth.isAdmin;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Research Admin'),
        actions: [
          if (widget.auth.session != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(
                child: Text(
                  widget.auth.session!.role,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
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
              Text('Studies', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              if (isAdmin) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Create a study', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        LayoutBuilder(builder: (context, constraints) {
                          final field = TextField(
                            key: const Key('new-study-name'),
                            controller: _name,
                            decoration: const InputDecoration(
                              labelText: 'Study name',
                            ),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _create(),
                          );
                          final button = FilledButton(
                            key: const Key('create-study'),
                            onPressed: c.creating ? null : _create,
                            child: Text(c.creating ? 'Creating...' : 'Create study'),
                          );
                          if (constraints.maxWidth < 420) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [field, const SizedBox(height: 8), button],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: field),
                              const SizedBox(width: 8),
                              button,
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (c.loading && !c.loadedOnce)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (c.studies.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.loadedOnce
                              ? (isAdmin
                                  ? 'There are no studies yet. Create the first one above.'
                                  : 'You are not a member of any study yet. Ask an administrator to add you.')
                              : 'Studies could not be loaded.',
                        ),
                        if (!c.loadedOnce) ...[
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: c.load,
                            child: const Text('Try again'),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < c.studies.length; i++) ...[
                        if (i > 0) const Divider(),
                        ListTile(
                          key: Key('study-${c.studies[i].id}'),
                          title: Text(c.studies[i].name),
                          subtitle: Text('Study ${c.studies[i].id}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => StudyScreen(
                                study: c.studies[i],
                                isAdmin: isAdmin,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
