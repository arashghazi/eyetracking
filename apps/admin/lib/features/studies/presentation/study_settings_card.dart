import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../application/study_settings_controller.dart';

/// Study settings for administrators: what happens to research rows when a
/// participant withdraws and erases their data.
class StudySettingsCard extends StatefulWidget {
  const StudySettingsCard({super.key, required this.studyId});

  final int studyId;

  @override
  State<StudySettingsCard> createState() => _StudySettingsCardState();
}

class _StudySettingsCardState extends State<StudySettingsCard> {
  late final StudySettingsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = StudySettingsController(
      AppScope.read(context).studies,
      widget.studyId,
    )..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        return Card(
          key: const Key('study-settings'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Study settings', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Retention policy: what happens to the research rows when a '
                  'participant withdraws and erases their data. The link to '
                  'the person is always removed.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                if (c.error != null) ...[
                  MessageBanner(message: c.error!, onDismiss: c.dismissError),
                  const SizedBox(height: 12),
                ],
                if (c.notice != null) ...[
                  MessageBanner(
                    message: c.notice!,
                    kind: BannerKind.success,
                    onDismiss: c.dismissNotice,
                  ),
                  const SizedBox(height: 12),
                ],
                if (c.study == null && !c.unreadable)
                  c.loading
                      ? const Center(child: CircularProgressIndicator())
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton(
                            key: const Key('retry-study-settings'),
                            onPressed: c.load,
                            child: const Text('Try again'),
                          ),
                        )
                else ...[
                  if (c.unreadable) ...[
                    const MessageBanner(
                      key: Key('retention-unreadable'),
                      message: 'You are not a member of this study, so its '
                          'current policy is not shown. You can still set it.',
                      kind: BannerKind.info,
                    ),
                    const SizedBox(height: 12),
                  ],
                  DropdownButtonFormField<String>(
                    key: const Key('retention-policy'),
                    initialValue: c.hasChoice ? c.draft : null,
                    isExpanded: true,
                    hint: const Text('Choose a policy'),
                    decoration:
                        const InputDecoration(labelText: 'Retention policy'),
                    items: [
                      for (final p in RetentionPolicy.all)
                        DropdownMenuItem(
                          value: p,
                          child: Text(RetentionPolicy.label(p)),
                        ),
                    ],
                    onChanged: c.saving
                        ? null
                        : (v) {
                            if (v != null) c.choose(v);
                          },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    c.hasChoice ? RetentionPolicy.explanation(c.draft) : '',
                    key: const Key('retention-explanation'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      key: const Key('save-retention-policy'),
                      onPressed: c.changed && !c.saving ? c.save : null,
                      child: Text(c.saving ? 'Saving...' : 'Save policy'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
