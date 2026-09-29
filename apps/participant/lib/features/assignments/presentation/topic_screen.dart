import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../application/topic_controller.dart';

/// "Confirm my topic": the short English interview of the interest path.
class TopicScreen extends StatefulWidget {
  const TopicScreen({super.key, required this.assignment, this.controller});

  final Assignment assignment;

  /// Tests pass a controller; otherwise one is built from the dependencies.
  final TopicController? controller;

  @override
  State<TopicScreen> createState() => _TopicScreenState();
}

class _TopicScreenState extends State<TopicScreen> {
  late final TopicController _controller;
  late final bool _owns;
  final _topicField = TextEditingController();
  final _freeField = TextEditingController();

  @override
  void initState() {
    super.initState();
    final provided = widget.controller;
    if (provided != null) {
      _controller = provided;
      _owns = false;
    } else {
      final deps = AppScope.read(context);
      _controller = TopicController(
        assignments: deps.assignments,
        profile: deps.profile,
        assignment: widget.assignment,
      );
      _owns = true;
    }
    _controller.load();
  }

  @override
  void dispose() {
    if (_owns) _controller.dispose();
    _topicField.dispose();
    _freeField.dispose();
    super.dispose();
  }

  void _pick(String interest) {
    _controller.pickInterest(interest);
    _topicField.text = _controller.topic;
    _topicField.selection =
        TextSelection.collapsed(offset: _topicField.text.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm my topic')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final c = _controller;
          return PageFrame(
            banner: c.error != null
                ? MessageBanner(message: c.error!, onDismiss: c.dismissError)
                : null,
            children: [
              if (c.submitted) _Submitted(onHome: () => Navigator.of(context).pop())
              else ..._form(context, c),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _form(BuildContext context, TopicController c) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What would you like to talk about?',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Your researcher prepares a short conversation about it. '
                'Pick one of your interests or type your own topic.',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
              const SizedBox(height: 12),
              if (c.loading)
                const Center(child: CircularProgressIndicator())
              else if (c.interests.isNotEmpty)
                Wrap(
                  key: const Key('interest-chips'),
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final i in c.interests)
                      ChoiceChip(
                        key: Key('interest-$i'),
                        label: Text(i),
                        selected: c.selectedInterest == i,
                        onSelected: (_) => _pick(i),
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('topic-field'),
                controller: _topicField,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Or type a topic',
                  hintText: 'For example: trains',
                ),
                onChanged: c.setTopic,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('free-text-field'),
                controller: _freeField,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Anything you would like the conversation to include?',
                  helperText: 'Optional',
                ),
                onChanged: c.setFreeText,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    key: const Key('topic-submit'),
                    onPressed: c.canSubmit ? c.submit : null,
                    child: Text(c.submitting ? 'Sending...' : 'Confirm topic'),
                  ),
                  TextButton(
                    key: const Key('topic-cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Not now'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
  }
}

class _Submitted extends StatelessWidget {
  const _Submitted({required this.onHome});

  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('topic-submitted'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Thank you. Your topic is saved.',
                      style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Content being prepared by your researcher',
              key: const Key('content-pending-note'),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'It will appear on your home screen when it is ready.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('topic-home'),
              onPressed: onHome,
              child: const Text('Back to home'),
            ),
          ],
        ),
      ),
    );
  }
}
