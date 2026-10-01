import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../ai/presentation/ai_widgets.dart' show MutedText;
import '../../live/presentation/face_layout_preview.dart';
import '../application/live_settings_draft.dart';
import '../application/protocol_editor_controller.dart';
import 'editor_widgets.dart';

/// The `live` section of the protocol editor: limits, scripted lines, avatar
/// and voice ids, input modes, transcript policy and the face layout.
class LiveSettingsSection extends StatelessWidget {
  const LiveSettingsSection({super.key, required this.controller});

  final ProtocolEditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final d = c.live;
    final ro = c.readOnly;
    final errors = c.liveErrors;
    final theme = Theme.of(context);

    Widget number(String key, String label, String value, void Function(String) set) =>
        EditorText(
          keyName: 'live-$key',
          label: label,
          revision: c.revision,
          value: value,
          enabled: !ro,
          width: 280,
          number: true,
          errorText: errors[key],
          onChanged: (v) => c.edit(() => set(v)),
        );

    Widget line(String key, String label, String value, void Function(String) set) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: EditorText(
            keyName: 'live-$key',
            label: label,
            revision: c.revision,
            value: value,
            enabled: !ro,
            minLines: 2,
            maxLines: 4,
            errorText: errors[key],
            counterText: '${value.length} / ${LiveRanges.lineMaxChars}',
            onChanged: (v) => c.edit(() => set(v)),
          ),
        );

    return EditorSection(
      key: const Key('live-section'),
      title: 'Live conversation',
      children: [
        const MutedText(
          'The avatar talks with the participant about the topic they '
          'confirmed. Every reply is checked on the server; a reply that '
          'breaks a rule is replaced by one of the scripted lines below.',
        ),
        const SizedBox(height: 16),
        Text('Limits', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 12, children: [
          number('max-turns', 'Max turns (${LiveRanges.maxTurns.min}-${LiveRanges.maxTurns.max})',
              d.maxTurns, (v) => d.maxTurns = v),
          number(
              'max-minutes',
              'Max minutes (${LiveRanges.maxMinutes.min}-${LiveRanges.maxMinutes.max})',
              d.maxMinutes,
              (v) => d.maxMinutes = v),
          number(
              'max-reply-words',
              'Max reply words (${LiveRanges.maxReplyWords.min}-${LiveRanges.maxReplyWords.max})',
              d.maxReplyWords,
              (v) => d.maxReplyWords = v),
          number(
              'max-participant-chars',
              'Max participant characters '
                  '(${LiveRanges.maxParticipantChars.min}-${LiveRanges.maxParticipantChars.max})',
              d.maxParticipantChars,
              (v) => d.maxParticipantChars = v),
        ]),
        const SizedBox(height: 16),
        Text('Scripted lines', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        const MutedText(
          '{{display_name}} and {{topic}} are filled in when a line is '
          'used. Links and e-mail addresses are not allowed.',
        ),
        const SizedBox(height: 8),
        line('opening-line', 'Opening line', d.openingLine, (v) => d.openingLine = v),
        line('closing-line', 'Closing line', d.closingLine, (v) => d.closingLine = v),
        line('redirect-line', 'Redirect line (back to the topic)', d.redirectLine,
            (v) => d.redirectLine = v),
        line('distress-line', 'Distress line (when the participant seems upset)',
            d.distressLine, (v) => d.distressLine = v),
        const SizedBox(height: 4),
        Text('Avatar', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        const MutedText(
          'For a future streaming avatar vendor. The development avatar '
          '(a sample video with the browser\'s voice) ignores both.',
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 12, children: [
          EditorText(
            keyName: 'live-avatar-id',
            label: 'Avatar id (optional)',
            revision: c.revision,
            value: d.avatarId,
            enabled: !ro,
            width: 280,
            errorText: errors['avatar-id'],
            onChanged: (v) => c.edit(() => d.avatarId = v),
          ),
          EditorText(
            keyName: 'live-voice-id',
            label: 'Voice id (optional)',
            revision: c.revision,
            value: d.voiceId,
            enabled: !ro,
            width: 280,
            errorText: errors['voice-id'],
            onChanged: (v) => c.edit(() => d.voiceId = v),
          ),
        ]),
        const SizedBox(height: 16),
        Text('Input and transcript', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        const MutedText('How the participant may answer. Typing always works.'),
        for (final mode in LiveInputMode.values)
          CheckboxListTile(
            key: Key('live-mode-${mode.wire}'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: Text(_modeLabel(mode)),
            value: mode == LiveInputMode.typed ? d.typed : d.speech,
            onChanged: ro
                ? null
                : (v) => c.edit(() {
                      if (mode == LiveInputMode.typed) {
                        d.typed = v ?? false;
                      } else {
                        d.speech = v ?? false;
                      }
                    }),
          ),
        if (errors['input-modes'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              errors['input-modes']!,
              key: const Key('live-modes-error'),
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
            ),
          ),
        EditorSwitch(
          keyName: 'live-store-transcript',
          title: 'Keep a written transcript when the participant agrees',
          value: d.storeTranscript,
          enabled: !ro,
          onChanged: (v) => c.edit(() => d.storeTranscript = v),
        ),
        const MutedText(
          'Without the participant\'s agreement, or with this off, the text '
          'is removed when the conversation ends; counts and flags stay. '
          'Audio is never kept.',
        ),
        const SizedBox(height: 16),
        Text('Face layout', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        const MutedText(
          'Optional. Where the face and its regions sit in the avatar frame, '
          'as fractions from 0 to 1 of the frame: x and y of the top left '
          'corner, w for width and h for height. The gaze regions are '
          'measured against it.',
        ),
        EditorSwitch(
          keyName: 'live-face-layout-switch',
          title: 'Describe the avatar\'s face layout',
          value: d.useFaceLayout,
          enabled: !ro,
          onChanged: c.setUseFaceLayout,
        ),
        if (d.useFaceLayout) _FaceLayoutEditor(controller: c, errors: errors),
      ],
    );
  }
}

String _modeLabel(LiveInputMode mode) => switch (mode) {
      LiveInputMode.typed => 'Typed',
      LiveInputMode.speech => 'Speech',
    };

class _FaceLayoutEditor extends StatelessWidget {
  const _FaceLayoutEditor({required this.controller, required this.errors});

  final ProtocolEditorController controller;
  final Map<String, String> errors;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final d = c.live;
    final broken = d.faceRuleBroken;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Wrap(
          spacing: 24,
          runSpacing: 16,
          children: [
            FaceLayoutPreview(
              key: const Key('face-layout-preview'),
              face: d.boxOf(FaceRegion.face),
              eye: d.boxOf(FaceRegion.eye),
              mouth: d.boxOf(FaceRegion.mouth),
              ruleBroken: broken,
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final region in FaceRegion.values) ...[
                  Text(region.label, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (var i = 0; i < 4; i++)
                      EditorText(
                        keyName: 'live-face-${region.key}-${kBoxAxes[i]}',
                        label: kBoxAxes[i],
                        revision: c.revision,
                        value: d.boxes[region]![i],
                        enabled: !c.readOnly,
                        width: 64,
                        number: true,
                        invalid:
                            errors['face-${region.key}-${kBoxAxes[i]}'] != null,
                        onChanged: (v) => c.edit(() => d.boxes[region]![i] = v),
                      ),
                  ]),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ],
        ),
        Text(
          broken ? LiveSettingsDraft.faceRuleMessage : _rule,
          key: const Key('face-layout-rule'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: broken ? AppColors.error : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        for (final entry in errors.entries)
          if (entry.key.startsWith('face-') && entry.key != 'face-rule')
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                entry.value,
                key: Key('error-${entry.key}'),
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
              ),
            ),
      ],
    );
  }

  static const String _rule =
      'The eye region must lie above the mouth region.';
}
