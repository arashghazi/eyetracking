import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../ai/application/video_jobs_controller.dart';
import '../../ai/presentation/ai_widgets.dart';
import '../application/content_editor_controller.dart';

/// Editor of one content item. Pass [contentId] to load an existing item, or
/// nothing to start a new draft.
class ContentEditorScreen extends StatefulWidget {
  const ContentEditorScreen({
    super.key,
    required this.studyId,
    required this.canEdit,
    this.contentId,
    this.onOpenAiTab,
  });

  final int studyId;
  final bool canEdit;
  final String? contentId;

  /// Switches the study screen to the AI tab after this editor closes.
  final VoidCallback? onOpenAiTab;

  @override
  State<ContentEditorScreen> createState() => _ContentEditorScreenState();
}

class _ContentEditorScreenState extends State<ContentEditorScreen> {
  ContentEditorController? _controller;
  late final VideoJobsController _video;
  bool _loading = false;
  String? _loadError;

  ContentEditorController _make(ContentDetail? detail) {
    final deps = AppScope.read(context);
    return ContentEditorController(
      deps.content,
      deps.mediaPicker,
      widget.studyId,
      initial: detail,
      canEdit: widget.canEdit,
    );
  }

  @override
  void initState() {
    super.initState();
    _video = VideoJobsController(AppScope.read(context).ai, widget.studyId);
    if (widget.contentId == null) {
      _controller = _make(null);
    } else {
      _loading = true;
      AppScope.read(context)
          .content
          .get(widget.studyId, widget.contentId!)
          .then((detail) {
        if (!mounted) return;
        setState(() {
          _controller = _make(detail);
          _loading = false;
        });
      }).catchError((Object e) {
        if (!mounted) return;
        setState(() {
          _loadError = userMessage(e);
          _loading = false;
        });
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _video.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(c == null || c.title.isEmpty ? 'Content' : c.title),
      ),
      body: c == null
          ? Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: MessageBanner(message: _loadError ?? 'Not found.'),
                    ),
            )
          : ListenableBuilder(
              listenable: c,
              builder: (context, _) => _Editor(
                controller: c,
                video: _video,
                onOpenAiTab: widget.onOpenAiTab,
              ),
            ),
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor({
    required this.controller,
    required this.video,
    this.onOpenAiTab,
  });

  final ContentEditorController controller;
  final VideoJobsController video;
  final VoidCallback? onOpenAiTab;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final ro = c.readOnly;
    return PageFrame(
      maxWidth: 1000,
      buildAll: true,
      banner: c.error != null
          ? MessageBanner(
              key: const Key('editor-error'),
              message: c.error!,
              onDismiss: c.dismissError,
            )
          : c.notice != null
              ? MessageBanner(
                  key: const Key('editor-notice'),
                  message: c.notice!,
                  kind: BannerKind.success,
                  onDismiss: c.dismissNotice,
                )
              : null,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(c.isNew ? 'New content' : 'Content',
                style: theme.textTheme.titleLarge),
            Container(
              key: const Key('content-status'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.isApproved
                    ? AppColors.successTint
                    : AppColors.warningTint,
                borderRadius: BorderRadius.circular(kRadius),
              ),
              child: Text(
                c.isApproved
                    ? 'Approved'
                    : (c.isNew ? 'Draft, not saved yet' : 'Draft'),
                style: theme.textTheme.labelMedium,
              ),
            ),
            StateChip(
              key: const Key('text-reviewed-status'),
              label: c.textReviewed ? 'Text reviewed: yes' : 'Text reviewed: no',
              foreground:
                  c.textReviewed ? AppColors.success : AppColors.textMuted,
              background:
                  c.textReviewed ? AppColors.successTint : const Color(0xFFEAEDED),
              icon: c.textReviewed
                  ? Icons.check_circle_outline
                  : Icons.rate_review_outlined,
            ),
            if (c.canEdit)
              OutlinedButton.icon(
                key: const Key('mark-text-reviewed'),
                onPressed: c.busy || c.isApproved || c.textReviewed
                    ? null
                    : c.markTextReviewed,
                icon: const Icon(Icons.task_alt, size: 18),
                label: const Text('Mark text reviewed'),
              ),
          ],
        ),
        if (c.isApproved) ...[
          const SizedBox(height: 8),
          const MessageBanner(
            key: Key('approved-note'),
            kind: BannerKind.info,
            message: 'Approved content cannot be edited.',
          ),
        ] else if (!c.canEdit) ...[
          const SizedBox(height: 8),
          const MessageBanner(
            kind: BannerKind.info,
            message: 'You have read-only access. Researchers of this study '
                'can edit content.',
          ),
        ],
        if (c.approveMissing.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            key: const Key('approve-missing'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warningTint,
              borderRadius: BorderRadius.circular(kRadius),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Missing media', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final key in c.approveMissing)
                  Text('•  $key', key: Key('missing-$key')),
                const SizedBox(height: 4),
                Text(
                  'Upload these files below, then approve again.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _Section(title: 'Basics', children: [
          _Text(
            keyName: 'content-title',
            label: 'Title',
            revision: c.revision,
            value: c.title,
            enabled: !ro,
            onChanged: (v) => c.edit(() => c.title = v),
          ),
          const SizedBox(height: 12),
          _TagsEditor(controller: c),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _Text(
              keyName: 'face-id',
              label: 'Face id',
              revision: c.revision,
              value: c.faceId,
              enabled: !ro,
              width: 240,
              onChanged: (v) => c.edit(() => c.faceId = v),
            ),
            _Text(
              keyName: 'voice-id',
              label: 'Voice id',
              revision: c.revision,
              value: c.voiceId,
              enabled: !ro,
              width: 240,
              onChanged: (v) => c.edit(() => c.voiceId = v),
            ),
          ]),
        ]),
        const SizedBox(height: 12),
        _Section(title: 'Segments', children: [
          Text(
            'Each segment is one video. Its question ends the segment: one '
            'option per line as Option=segment (the segment that plays next). '
            'An option without a segment ends the conversation. The text may '
            'use {{display_name}} and {{topic}}.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < c.segments.length; i++) ...[
            _SegmentRow(controller: c, index: i, segment: c.segments[i]),
            const SizedBox(height: 8),
          ],
          if (!ro)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('add-segment'),
                onPressed: c.addSegment,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add segment'),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _SegmentDrop(
              keyName: 'start-segment',
              label: 'First segment',
              value: c.startSegment,
              ids: c.segmentIds,
              allowNone: false,
              enabled: !ro,
              revision: c.revision,
              onChanged: (v) => c.edit(() => c.startSegment = v),
            ),
            _SegmentDrop(
              keyName: 'post-segment',
              label: 'Post observation segment',
              value: c.postSegment,
              ids: c.segmentIds,
              allowNone: true,
              enabled: !ro,
              revision: c.revision,
              onChanged: (v) => c.edit(() => c.postSegment = v),
            ),
          ]),
        ]),
        const SizedBox(height: 12),
        _Section(title: 'Comprehension questions', children: [
          if (c.comprehension.isEmpty)
            const Text('None. They are asked after the conversation.',
                key: Key('no-comprehension')),
          for (var i = 0; i < c.comprehension.length; i++) ...[
            _ComprehensionRow(
                controller: c, index: i, item: c.comprehension[i]),
            const SizedBox(height: 8),
          ],
          if (!ro)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('add-comprehension'),
                onPressed: c.addComprehension,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add question'),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        _MediaSection(controller: c),
        const SizedBox(height: 12),
        _VideoSection(
          controller: c,
          video: video,
          onOpenAiTab: onOpenAiTab,
        ),
        const SizedBox(height: 16),
        if (!ro)
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(
              key: const Key('save-content'),
              onPressed: c.busy ? null : c.save,
              child: Text(c.busy ? 'Working...' : 'Save draft'),
            ),
            OutlinedButton(
              key: const Key('approve-content'),
              onPressed: c.busy ? null : c.approve,
              child: const Text('Approve'),
            ),
          ]),
      ],
    );
  }
}

class _TagsEditor extends StatefulWidget {
  const _TagsEditor({required this.controller});

  final ContentEditorController controller;

  @override
  State<_TagsEditor> createState() => _TagsEditorState();
}

class _TagsEditorState extends State<_TagsEditor> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _add() {
    widget.controller.addTag(_field.text);
    _field.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Topic tags', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final t in c.tags)
              InputChip(
                key: Key('tag-$t'),
                label: Text(t),
                onDeleted: c.readOnly ? null : () => c.removeTag(t),
              ),
            if (c.tags.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No tags yet.'),
              ),
          ],
        ),
        if (!c.readOnly) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('tag-field'),
                  controller: _field,
                  decoration: const InputDecoration(
                    labelText: 'Add a topic tag',
                    hintText: 'For example: trains',
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                key: const Key('add-tag'),
                onPressed: _add,
                child: const Text('Add'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    required this.controller,
    required this.index,
    required this.segment,
  });

  final ContentEditorController controller;
  final int index;
  final SegmentDraft segment;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final ro = c.readOnly;
    final k = 'segment-$index';
    final rev = c.revision * 1000 + segment.uid;
    return Container(
      key: Key('$k-row'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Segment ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              if (!ro)
                IconButton(
                  key: Key('$k-remove'),
                  tooltip: 'Remove segment',
                  onPressed: c.segments.length > 1
                      ? () => c.removeSegment(segment.uid)
                      : null,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _Text(
              keyName: '$k-id',
              label: 'Id',
              revision: rev,
              value: segment.id,
              enabled: !ro,
              width: 110,
              onChanged: (v) => c.edit(() => segment.id = v),
            ),
            _Text(
              keyName: '$k-media',
              label: 'Media key',
              revision: rev,
              value: segment.mediaKey,
              enabled: !ro,
              width: 200,
              onChanged: (v) => c.edit(() => segment.mediaKey = v),
            ),
            _Text(
              keyName: '$k-duration',
              label: 'Duration (s)',
              revision: rev,
              value: segment.duration,
              enabled: !ro,
              width: 120,
              number: true,
              onChanged: (v) => c.edit(() => segment.duration = v),
            ),
          ]),
          const SizedBox(height: 12),
          _Text(
            keyName: '$k-text',
            label: 'Text',
            revision: rev,
            value: segment.text,
            enabled: !ro,
            lines: 2,
            onChanged: (v) => c.edit(() => segment.text = v),
          ),
          const SizedBox(height: 12),
          _Text(
            keyName: '$k-question',
            label: 'Question prompt (leave empty when the conversation ends here)',
            revision: rev,
            value: segment.questionPrompt,
            enabled: !ro,
            onChanged: (v) => c.edit(() => segment.questionPrompt = v),
          ),
          const SizedBox(height: 12),
          _Text(
            keyName: '$k-options',
            label: 'Options, one per line as Option=segment',
            revision: rev,
            value: segment.optionText,
            enabled: !ro,
            lines: 3,
            onChanged: (v) => c.edit(() => segment.optionText = v),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _Text(
              keyName: '$k-face',
              label: 'Face box x, y, w, h (0-1)',
              revision: rev,
              value: segment.faceBox,
              enabled: !ro,
              width: 240,
              onChanged: (v) => c.edit(() => segment.faceBox = v),
            ),
            _Text(
              keyName: '$k-eyes',
              label: 'Eye region x, y, w, h',
              revision: rev,
              value: segment.eyeRegion,
              enabled: !ro,
              width: 240,
              onChanged: (v) => c.edit(() => segment.eyeRegion = v),
            ),
            _Text(
              keyName: '$k-mouth',
              label: 'Mouth region x, y, w, h',
              revision: rev,
              value: segment.mouthRegion,
              enabled: !ro,
              width: 240,
              onChanged: (v) => c.edit(() => segment.mouthRegion = v),
            ),
          ]),
        ],
      ),
    );
  }
}

class _ComprehensionRow extends StatelessWidget {
  const _ComprehensionRow({
    required this.controller,
    required this.index,
    required this.item,
  });

  final ContentEditorController controller;
  final int index;
  final ComprehensionDraft item;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final ro = c.readOnly;
    final k = 'comprehension-$index';
    final rev = c.revision * 1000 + item.uid;
    return Container(
      key: Key('$k-row'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Question ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              if (!ro)
                IconButton(
                  key: Key('$k-remove'),
                  tooltip: 'Remove question',
                  onPressed: () => c.removeComprehension(item.uid),
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _Text(
              keyName: '$k-id',
              label: 'Id',
              revision: rev,
              value: item.id,
              enabled: !ro,
              width: 110,
              onChanged: (v) => c.edit(() => item.id = v),
            ),
            _Text(
              keyName: '$k-correct',
              label: 'Correct option',
              revision: rev,
              value: item.correct,
              enabled: !ro,
              width: 220,
              onChanged: (v) => c.edit(() => item.correct = v),
            ),
          ]),
          const SizedBox(height: 12),
          _Text(
            keyName: '$k-prompt',
            label: 'Question',
            revision: rev,
            value: item.prompt,
            enabled: !ro,
            onChanged: (v) => c.edit(() => item.prompt = v),
          ),
          const SizedBox(height: 12),
          _Text(
            keyName: '$k-options',
            label: 'Options, one per line',
            revision: rev,
            value: item.optionText,
            enabled: !ro,
            lines: 3,
            onChanged: (v) => c.edit(() => item.optionText = v),
          ),
        ],
      ),
    );
  }
}

class _MediaSection extends StatelessWidget {
  const _MediaSection({required this.controller});

  final ContentEditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final keys = c.mediaKeys;
    return _Section(title: 'Media', children: [
      Text(
        'One file per media key: WebM or MP4 video, or a PNG or JPEG image, '
        'up to 200 MB. Approval needs every key uploaded.',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 8),
      if (keys.isEmpty)
        const Text('No media keys yet. Give a segment a media key.',
            key: Key('no-media-keys')),
      for (final key in keys) ...[
        _MediaRow(controller: c, mediaKey: key),
        const Divider(height: 16),
      ],
    ]);
  }
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({required this.controller, required this.mediaKey});

  final ContentEditorController controller;
  final String mediaKey;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final state = c.uploadOf(mediaKey);
    final missing = c.isMissing(mediaKey);
    final (label, color) = state.uploading
        ? ('Uploading', AppColors.textMuted)
        : missing
            ? ('Missing', AppColors.warning)
            : ('Uploaded', AppColors.success);
    return Column(
      key: Key('media-row-$mediaKey'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(mediaKey,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontFamily: 'monospace',
                  fontFamilyFallback: kMonospaceFallback,
                )),
            Text(label,
                key: Key('media-state-$mediaKey'),
                style: theme.textTheme.labelMedium?.copyWith(color: color)),
            if (!c.readOnly)
              OutlinedButton(
                key: Key('upload-$mediaKey'),
                onPressed:
                    state.uploading || c.busy ? null : () => c.uploadMedia(mediaKey),
                child: Text(missing ? 'Upload file' : 'Replace file'),
              ),
          ],
        ),
        if (state.uploading) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  key: Key('progress-$mediaKey'),
                  value: state.progress,
                ),
              ),
              const SizedBox(width: 8),
              Text('${((state.progress ?? 0) * 100).floor()} %',
                  key: Key('progress-text-$mediaKey')),
            ],
          ),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 4),
          Text(state.error!,
              key: Key('upload-error-$mediaKey'),
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error)),
        ],
      ],
    );
  }
}

/// "Generate videos": one AI video job per segment that has no media yet.
class _VideoSection extends StatelessWidget {
  const _VideoSection({
    required this.controller,
    required this.video,
    this.onOpenAiTab,
  });

  final ContentEditorController controller;
  final VideoJobsController video;
  final VoidCallback? onOpenAiTab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([controller, video]),
      builder: (context, _) {
        final c = controller;
        final lacking = c.segmentsWithoutMedia;
        final candidates = [for (final s in lacking) s.id.trim()];
        final blocked = c.videoBlockedReason ??
            (video.selectedOf(candidates).isEmpty
                ? 'Select at least one segment.'
                : null);
        return _Section(
          key: const Key('video-section'),
          title: 'Generate videos',
          children: [
            Text(
              'Creates one video job for each segment that has no media yet. '
              'The generated video is stored like an upload. Needs reviewed '
              'text.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (video.error != null) ...[
              MessageBanner(
                key: const Key('video-error'),
                message: video.error!,
                onDismiss: video.dismissError,
              ),
              const SizedBox(height: 12),
            ],
            Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(
                width: 240,
                child: TextFormField(
                  key: const Key('video-face-id'),
                  initialValue: video.faceId,
                  decoration: const InputDecoration(
                    labelText: 'Face id',
                    helperText: 'Empty: the content\'s own',
                  ),
                  onChanged: (v) => video.faceId = v,
                ),
              ),
              SizedBox(
                width: 240,
                child: TextFormField(
                  key: const Key('video-voice-id'),
                  initialValue: video.voiceId,
                  decoration: const InputDecoration(
                    labelText: 'Voice id',
                    helperText: 'Empty: the content\'s own',
                  ),
                  onChanged: (v) => video.voiceId = v,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text('Segments without media',
                style: theme.textTheme.labelLarge),
            if (lacking.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('None.', key: Key('no-lacking-segments')),
              ),
            for (final s in lacking)
              CheckboxListTile(
                key: Key('video-segment-${s.id.trim()}'),
                value: video.isSelected(s.id.trim()),
                onChanged: c.canEdit
                    ? (v) => video.select(s.id.trim(), v ?? false)
                    : null,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('Segment ${s.id.trim()}'),
                subtitle: Text(s.mediaKey.trim()),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  key: const Key('generate-videos'),
                  onPressed: blocked != null || video.busy
                      ? null
                      : () => video.generate(c.id!, candidates),
                  icon: const Icon(Icons.movie_creation_outlined, size: 18),
                  label: Text(video.busy ? 'Working...' : 'Generate videos'),
                ),
                if (blocked != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Text(
                      blocked,
                      key: const Key('video-blocked-reason'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.warning),
                    ),
                  ),
              ],
            ),
            if (video.created.isNotEmpty) ...[
              const SizedBox(height: 12),
              Column(
                key: const Key('video-jobs-created'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${video.created.length} video '
                    '${video.created.length == 1 ? 'job' : 'jobs'} created',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  for (final j in video.created)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Job ${j.id}, segment ${j.segmentId ?? '-'}',
                              key: Key('video-job-${j.id}')),
                          JobStatusChip(status: j.status),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    key: const Key('open-ai-tab'),
                    onPressed: () {
                      Navigator.of(context).maybePop();
                      onOpenAiTab?.call();
                    },
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Open the AI tab'),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SegmentDrop extends StatelessWidget {
  const _SegmentDrop({
    required this.keyName,
    required this.label,
    required this.value,
    required this.ids,
    required this.allowNone,
    required this.enabled,
    required this.revision,
    required this.onChanged,
  });

  final String keyName;
  final String label;
  final String value;
  final List<String> ids;
  final bool allowNone;
  final bool enabled;
  final int revision;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = [if (allowNone) '', ...ids];
    return SizedBox(
      width: 260,
      child: KeyedSubtree(
        key: ValueKey('$keyName-$revision-${ids.join(',')}'),
        child: DropdownButtonFormField<String>(
          key: Key(keyName),
          initialValue: options.contains(value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final o in options)
              DropdownMenuItem(value: o, child: Text(o.isEmpty ? 'None' : o)),
          ],
          onChanged: enabled ? (v) => onChanged(v ?? '') : null,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );
}

class _Text extends StatelessWidget {
  const _Text({
    required this.keyName,
    required this.label,
    required this.revision,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.width,
    this.number = false,
    this.lines = 1,
  });

  final String keyName;
  final String label;
  final int revision;
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final double? width;
  final bool number;
  final int lines;

  @override
  Widget build(BuildContext context) {
    final field = KeyedSubtree(
      key: ValueKey('$keyName-$revision'),
      child: TextFormField(
        key: Key(keyName),
        initialValue: value,
        enabled: enabled,
        minLines: lines,
        maxLines: lines == 1 ? 1 : lines + 2,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : (lines > 1 ? TextInputType.multiline : TextInputType.text),
        decoration: InputDecoration(labelText: label),
        onChanged: onChanged,
      ),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }
}
