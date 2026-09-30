import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../application/text_job_form_controller.dart';

/// "Generate conversation text": creates a draft content item filled by a
/// text job, either for a participant's assignment or free-form.
class TextJobCard extends StatefulWidget {
  const TextJobCard({
    super.key,
    required this.studyId,
    required this.onCreated,
    this.sendFreeText = false,
  });

  final int studyId;
  final void Function(AiJob job) onCreated;

  /// Study setting: the participant's free-text topic is sent to the model.
  final bool sendFreeText;

  @override
  State<TextJobCard> createState() => _TextJobCardState();
}

class _TextJobCardState extends State<TextJobCard> {
  late final TextJobFormController _form;
  final _code = TextEditingController();
  final _interest = TextEditingController();

  @override
  void initState() {
    super.initState();
    final deps = AppScope.read(context);
    _form = TextJobFormController(
      deps.ai,
      deps.assignments,
      widget.studyId,
      onCreated: widget.onCreated,
    );
  }

  @override
  void dispose() {
    _form.dispose();
    _code.dispose();
    _interest.dispose();
    super.dispose();
  }

  void _addInterest() {
    _form.addInterest(_interest.text);
    _interest.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _form,
      builder: (context, _) {
        final f = _form;
        final errors = f.fieldErrors;
        return Card(
          key: const Key('text-job-card'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Generate conversation text',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Creates a draft content item. Generated text is always a '
                  'draft: nothing reaches a participant before you review it, '
                  'approve it and attach it to the assignment.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                if (f.error != null) ...[
                  MessageBanner(
                    key: const Key('text-job-error'),
                    message: f.error!,
                    onDismiss: f.dismissError,
                  ),
                  const SizedBox(height: 12),
                ] else if (f.notice != null) ...[
                  MessageBanner(
                    key: const Key('text-job-notice'),
                    message: f.notice!,
                    kind: BannerKind.success,
                    onDismiss: f.dismissNotice,
                  ),
                  const SizedBox(height: 12),
                ],
                SegmentedButton<TextJobMode>(
                  key: const Key('text-job-mode'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: TextJobMode.assignment,
                      label: Text('For an assignment'),
                    ),
                    ButtonSegment(
                      value: TextJobMode.freeForm,
                      label: Text('Free form'),
                    ),
                  ],
                  selected: {f.mode},
                  onSelectionChanged: (v) => f.setMode(v.first),
                  style: SegmentedButton.styleFrom(
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(kRadius)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (f.isAssignmentMode)
                  _assignmentPart(context, f, errors)
                else
                  _freeFormPart(context, f, errors),
                const SizedBox(height: 12),
                _sharedPart(f, errors),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('generate-text'),
                  onPressed: f.busy ? null : f.submit,
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: Text(f.busy ? 'Working...' : 'Generate text'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _assignmentPart(
    BuildContext context,
    TextJobFormController f,
    Map<String, String> errors,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                key: const Key('job-participant-code'),
                controller: _code,
                decoration: InputDecoration(
                  labelText: 'Participant code',
                  hintText: 'For example: P-001',
                  errorText: errors['code'],
                ),
                onChanged: f.codeChanged,
                onSubmitted: (_) => f.loadAssignments(),
              ),
            ),
            OutlinedButton.icon(
              key: const Key('find-assignments'),
              onPressed: f.loadingAssignments ? null : f.loadAssignments,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Find assignments'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (f.loadingAssignments)
          const Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (f.assignmentsError != null)
          Text(
            f.assignmentsError!,
            key: const Key('assignments-load-error'),
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.error),
          )
        else if (f.assignmentsLoaded && f.waitingAssignments.isEmpty)
          Text(
            'No assignment of ${f.participantCode.trim()} is waiting for a '
            'topic or for content.',
            key: const Key('no-waiting-assignments'),
          )
        else if (f.waitingAssignments.isNotEmpty)
          RadioGroup<String>(
            groupValue: f.assignmentId,
            onChanged: f.selectAssignment,
            child: Column(
              key: const Key('waiting-assignments'),
              children: [
                for (final a in f.waitingAssignments)
                  RadioListTile<String>(
                    key: Key('job-assignment-${a.id}'),
                    value: a.id,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('#${a.id}  ${a.protocol.name}'),
                    subtitle: Text([
                      assignmentStatusLabel(a.status),
                      if (a.topic != null) 'topic: ${a.topic}',
                    ].join(', ')),
                  ),
              ],
            ),
          ),
        if (errors['assignment'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              errors['assignment']!,
              key: const Key('assignment-error'),
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          widget.sendFreeText
              ? 'The topic, display name and interests come from the '
                  'assignment and the profile. This study sends the '
                  "participant's free-text topic to the text provider."
              : 'The topic, display name and interests come from the '
                  'assignment and the profile. The '
                  "participant's free-text topic is not sent to the text "
                  'provider.',
          key: const Key('free-text-note'),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _freeFormPart(
    BuildContext context,
    TextJobFormController f,
    Map<String, String> errors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            SizedBox(
              width: 320,
              child: TextFormField(
                key: const Key('job-topic'),
                initialValue: f.topic,
                decoration: InputDecoration(
                  labelText: 'Topic',
                  hintText: 'For example: trains',
                  errorText: errors['topic'],
                ),
                onChanged: (v) => f.topic = v,
              ),
            ),
            SizedBox(
              width: 220,
              child: TextFormField(
                key: const Key('job-display-name'),
                initialValue: f.displayName,
                decoration: const InputDecoration(labelText: 'Display name'),
                onChanged: (v) => f.displayName = v,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Interests', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final t in f.interests)
              InputChip(
                key: Key('interest-$t'),
                label: Text(t),
                onDeleted: () => f.removeInterest(t),
              ),
            if (f.interests.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No interests yet.'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                key: const Key('job-interest-field'),
                controller: _interest,
                decoration:
                    const InputDecoration(labelText: 'Add an interest'),
                onSubmitted: (_) => _addInterest(),
              ),
            ),
            OutlinedButton(
              key: const Key('add-interest'),
              onPressed: _addInterest,
              child: const Text('Add'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sharedPart(TextJobFormController f, Map<String, String> errors) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: [
        SizedBox(
          width: 160,
          child: TextFormField(
            key: const Key('job-points'),
            initialValue: f.interactionPoints,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Interaction points (0-5)',
              errorText: errors['points'],
              errorMaxLines: 3,
            ),
            onChanged: (v) => f.interactionPoints = v,
          ),
        ),
        SizedBox(
          width: 160,
          child: TextFormField(
            key: const Key('job-length'),
            initialValue: f.lengthSeconds,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Length (s, 30-600)',
              errorText: errors['length'],
              errorMaxLines: 3,
            ),
            onChanged: (v) => f.lengthSeconds = v,
          ),
        ),
        SizedBox(
          width: 260,
          child: TextField(
            key: const Key('job-title'),
            decoration: const InputDecoration(
              labelText: 'Title (optional)',
              hintText: 'Default: AI draft: <topic>',
            ),
            onChanged: (v) => f.title = v,
          ),
        ),
        SizedBox(
          width: 160,
          child: TextField(
            key: const Key('job-face'),
            decoration: const InputDecoration(labelText: 'Face id'),
            onChanged: (v) => f.faceId = v,
          ),
        ),
        SizedBox(
          width: 160,
          child: TextField(
            key: const Key('job-voice'),
            decoration: const InputDecoration(labelText: 'Voice id'),
            onChanged: (v) => f.voiceId = v,
          ),
        ),
      ],
    );
  }
}
