import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../ai/presentation/ai_widgets.dart' show MutedText;
import '../application/debrief_form_controller.dart';
import 'pilot_widgets.dart';

/// Questions after a session: the short, versioned form a participant may
/// answer once a session has ended. Researchers edit; analysts read.
class DebriefSection extends StatelessWidget {
  const DebriefSection({super.key, required this.controller});

  final DebriefFormController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.error != null) ...[
              MessageBanner(
                key: const Key('debrief-error'),
                message: c.error!,
                onDismiss: c.dismissError,
              ),
              const SizedBox(height: 12),
            ] else if (c.notice != null) ...[
              MessageBanner(
                key: const Key('debrief-notice'),
                kind: BannerKind.success,
                message: c.notice!,
                onDismiss: c.dismissNotice,
              ),
              const SizedBox(height: 12),
            ],
            if (c.form == null)
              c.loading
                  ? const BusyBox()
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        key: const Key('debrief-retry'),
                        onPressed: c.load,
                        child: const Text('Try again'),
                      ),
                    )
            else ...[
              _HeaderCard(controller: c),
              const SizedBox(height: 12),
              PilotCard(
                title: 'Questions',
                caption: c.canEdit
                    ? 'Keys name the answer columns in the exports. Use a-z, '
                        '0-9 and _, starting with a letter.'
                    : null,
                children: [
                  if (c.listProblem != null) ...[
                    Text(
                      c.listProblem!,
                      key: const Key('debrief-list-problem'),
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.error),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (c.drafts.isEmpty)
                    const EmptyNote('The form has no questions.')
                  else
                    for (var i = 0; i < c.drafts.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      c.canEdit
                          ? _QuestionEditor(
                              key: ValueKey('draft-${c.drafts[i].uid}'),
                              controller: c,
                              draft: c.drafts[i],
                              index: i,
                            )
                          : _QuestionReadOnly(
                              key: ValueKey('draft-${c.drafts[i].uid}'),
                              draft: c.drafts[i],
                              index: i,
                            ),
                    ],
                  if (c.canEdit) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('debrief-add'),
                          onPressed: c.canAdd ? c.add : null,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add question'),
                        ),
                        FilledButton(
                          key: const Key('debrief-save'),
                          onPressed: c.canSave ? c.save : null,
                          child: Text(c.saving ? 'Saving...' : 'Save'),
                        ),
                        OutlinedButton(
                          key: const Key('debrief-discard'),
                          onPressed: c.dirty && !c.saving ? c.discard : null,
                          child: const Text('Discard changes'),
                        ),
                      ],
                    ),
                    if (!c.canAdd) ...[
                      const SizedBox(height: 6),
                      const MutedText('A form holds at most 20 questions.'),
                    ],
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.controller});

  final DebriefFormController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    return PilotCard(
      title: 'Questions after a session',
      trailing: Text(
        c.saved ? 'Version ${c.version}' : 'Not saved yet',
        key: const Key('debrief-version'),
        style: theme.textTheme.labelLarge,
      ),
      caption: 'A short form a participant may answer when a session has '
          'ended, or skip. Answers are stored under the research code.',
      children: [
        if (c.canEdit)
          SwitchListTile(
            key: const Key('debrief-enabled'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Ask participants these questions after a session'),
            value: c.enabled,
            onChanged: c.saving ? null : c.setEnabled,
          )
        else
          Text(
            c.enabled
                ? 'Participants are asked these questions after a session.'
                : 'Participants are not asked these questions.',
            key: const Key('debrief-enabled-readonly'),
          ),
        const SizedBox(height: 4),
        const MutedText(
          'Changing the questions creates a new version, and answers already '
          'given keep the version they were answered for. Switching the form '
          'on or off does not create a version.',
        ),
        if (!c.saved) ...[
          const SizedBox(height: 4),
          const MutedText(
            'Nothing is saved yet. These are suggested questions; saving '
            'stores them as version 1.',
          ),
        ],
        if (c.canEdit && c.questionsChanged && c.saved) ...[
          const SizedBox(height: 8),
          Text(
            'Saving will create version ${c.version + 1}.',
            key: const Key('debrief-will-version'),
            style: theme.textTheme.labelLarge,
          ),
        ],
        if (!c.canEdit) ...[
          const SizedBox(height: 8),
          const MessageBanner(
            key: Key('debrief-read-only'),
            kind: BannerKind.info,
            message: 'You have read-only access. Researchers of this study '
                'can change the questions.',
          ),
        ],
      ],
    );
  }
}

class _QuestionEditor extends StatelessWidget {
  const _QuestionEditor({
    super.key,
    required this.controller,
    required this.draft,
    required this.index,
  });

  final DebriefFormController controller;
  final DebriefDraft draft;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final d = draft;
    final theme = Theme.of(context);
    final problem = c.problemFor(d.uid);
    final last = index == c.drafts.length - 1;
    return Container(
      key: Key('question-$index'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: problem == null ? AppColors.border : AppColors.error),
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Question ${index + 1}', style: theme.textTheme.titleSmall),
              ),
              IconButton(
                key: Key('q-up-$index'),
                tooltip: 'Move up',
                onPressed: index == 0 ? null : () => c.move(d, -1),
                icon: const Icon(Icons.arrow_upward, size: 18),
              ),
              IconButton(
                key: Key('q-down-$index'),
                tooltip: 'Move down',
                onPressed: last ? null : () => c.move(d, 1),
                icon: const Icon(Icons.arrow_downward, size: 18),
              ),
              IconButton(
                key: Key('q-remove-$index'),
                tooltip: 'Remove question',
                onPressed: () => c.remove(d),
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ],
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              WrapItem(
                width: 240,
                child: TextFormField(
                  key: Key('q-key-$index'),
                  initialValue: d.key,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: 'Key'),
                  onChanged: (v) => c.edit(d, (x) => x.key = v),
                ),
              ),
              WrapItem(
                width: 180,
                child: DropdownButtonFormField<String>(
                  key: Key('q-type-$index'),
                  initialValue: d.type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    for (final t in DebriefQuestionType.all)
                      DropdownMenuItem(
                        value: t,
                        child: Text(debriefQuestionTypeLabel(t)),
                      ),
                  ],
                  onChanged: (v) => v == null ? null : c.edit(d, (x) => x.type = v),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    key: Key('q-required-$index'),
                    value: d.required,
                    onChanged: (v) => c.edit(d, (x) => x.required = v ?? false),
                  ),
                  const Text('Required'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: Key('q-prompt-$index'),
            initialValue: d.prompt,
            minLines: 1,
            maxLines: 3,
            maxLength: DebriefQuestion.maxPromptChars,
            decoration: const InputDecoration(labelText: 'Prompt'),
            onChanged: (v) => c.edit(d, (x) => x.prompt = v),
          ),
          if (d.type == DebriefQuestionType.scale) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: [
                WrapItem(
                  width: 140,
                  child: TextFormField(
                    key: Key('q-scale-max-$index'),
                    initialValue: d.scaleMax,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Scale max',
                      helperText: '2 to 10',
                    ),
                    onChanged: (v) => c.edit(d, (x) => x.scaleMax = v),
                  ),
                ),
                WrapItem(
                  width: 320,
                  child: TextFormField(
                    key: Key('q-labels-$index'),
                    initialValue: d.labelsText,
                    minLines: 2,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Labels (optional)',
                      helperText: 'One line per point, from 1 up.',
                    ),
                    onChanged: (v) => c.edit(d, (x) => x.labelsText = v),
                  ),
                ),
              ],
            ),
          ],
          if (d.type == DebriefQuestionType.choice) ...[
            const SizedBox(height: 8),
            TextFormField(
              key: Key('q-options-$index'),
              initialValue: d.optionsText,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Options',
                helperText: 'One line per option, 2 to 10.',
              ),
              onChanged: (v) => c.edit(d, (x) => x.optionsText = v),
            ),
          ],
          if (problem != null) ...[
            const SizedBox(height: 8),
            Text(
              problem,
              key: Key('q-problem-$index'),
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuestionReadOnly extends StatelessWidget {
  const _QuestionReadOnly({super.key, required this.draft, required this.index});

  final DebriefDraft draft;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = draft.toQuestion();
    final detail = switch (q.type) {
      DebriefQuestionType.scale => 'Scale 1 to ${q.scaleMax}'
          '${q.labels.isEmpty ? '' : ': ${q.labels.join(', ')}'}',
      DebriefQuestionType.choice => 'Choice: ${q.options.join(', ')}',
      _ => debriefQuestionTypeLabel(q.type),
    };
    return Container(
      key: Key('question-$index'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${index + 1}. ${q.prompt}', style: theme.textTheme.bodyLarge),
          const SizedBox(height: 2),
          Text(
            '${q.key}, $detail${q.required ? ', required' : ''}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
