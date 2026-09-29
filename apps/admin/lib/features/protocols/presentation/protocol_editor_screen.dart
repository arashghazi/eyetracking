import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../application/protocol_editor_controller.dart';

/// Editor of one protocol. Pass [initial] to edit a protocol that is already
/// loaded, [protocolId] to load it, or neither to start a new draft.
class ProtocolEditorScreen extends StatefulWidget {
  const ProtocolEditorScreen({
    super.key,
    required this.studyId,
    required this.canEdit,
    this.protocolId,
    this.initial,
  });

  final int studyId;
  final bool canEdit;
  final String? protocolId;
  final ProtocolDetail? initial;

  @override
  State<ProtocolEditorScreen> createState() => _ProtocolEditorScreenState();
}

class _ProtocolEditorScreenState extends State<ProtocolEditorScreen> {
  ProtocolEditorController? _controller;
  bool _loading = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    final deps = AppScope.read(context);
    if (widget.protocolId != null && widget.initial == null) {
      _loading = true;
      deps.protocols.get(widget.studyId, widget.protocolId!).then((detail) {
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
    } else {
      _controller = _make(widget.initial);
    }
  }

  ProtocolEditorController _make(ProtocolDetail? detail) =>
      ProtocolEditorController(
        AppScope.read(context).protocols,
        widget.studyId,
        initial: detail,
        canEdit: widget.canEdit,
      );

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _confirmPublish(ProtocolEditorController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('publish-dialog'),
        title: const Text('Publish this protocol?'),
        content: const Text(
          'Published versions cannot be edited. To change it later you make '
          'a new draft from it.',
        ),
        actions: [
          TextButton(
            key: const Key('publish-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('publish-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    if (ok == true) await c.publish();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(c == null || c.name.isEmpty ? 'Protocol' : c.name),
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
                onPublish: () => _confirmPublish(c),
              ),
            ),
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor({required this.controller, required this.onPublish});

  final ProtocolEditorController controller;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final ro = c.readOnly;
    final gradual = c.path == ProtocolPath.gradualFace;
    return PageFrame(
      maxWidth: 960,
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
            Text(c.isNew ? 'New protocol' : 'Protocol',
                style: theme.textTheme.titleLarge),
            _StatusLabel(controller: c),
          ],
        ),
        if (c.isPublished) ...[
          const SizedBox(height: 8),
          const MessageBanner(
            key: Key('published-note'),
            kind: BannerKind.info,
            message: 'Published versions cannot be edited. Make a new draft '
                'from it to change something.',
          ),
        ] else if (!c.canEdit) ...[
          const SizedBox(height: 8),
          const MessageBanner(
            kind: BannerKind.info,
            message: 'You have read-only access. Researchers of this study '
                'can edit protocols.',
          ),
        ],
        const SizedBox(height: 12),
        _Section(title: 'Basics', children: [
          _Text(
            keyName: 'protocol-name',
            label: 'Name',
            revision: c.revision,
            value: c.name,
            enabled: !ro,
            onChanged: (v) => c.edit(() => c.name = v),
          ),
          const SizedBox(height: 12),
          _Drop<ProtocolPath>(
            keyName: 'protocol-path',
            label: 'Path',
            revision: c.revision,
            value: c.path,
            enabled: !ro,
            items: {for (final p in ProtocolPath.values) p: p.label},
            onChanged: c.setPath,
          ),
        ]),
        const SizedBox(height: 12),
        _Section(title: 'Timing', children: [
          Wrap(spacing: 12, runSpacing: 12, children: [
            _Text(
              keyName: 'baseline-seconds',
              label: 'Baseline seconds',
              revision: c.revision,
              value: c.baselineSeconds,
              enabled: !ro,
              width: 180,
              number: true,
              onChanged: (v) => c.edit(() => c.baselineSeconds = v),
            ),
            _Text(
              keyName: 'post-seconds',
              label: 'Post seconds',
              revision: c.revision,
              value: c.postSeconds,
              enabled: !ro,
              width: 180,
              number: true,
              onChanged: (v) => c.edit(() => c.postSeconds = v),
            ),
          ]),
        ]),
        const SizedBox(height: 12),
        _Section(title: 'Comfort scale', children: [
          Wrap(spacing: 12, runSpacing: 12, children: [
            _Drop<int>(
              keyName: 'scale-max',
              label: 'Number of values',
              revision: c.revision,
              value: c.scaleMax,
              enabled: !ro,
              width: 180,
              items: {for (var v = 3; v <= 7; v++) v: '$v'},
              onChanged: c.setScaleMax,
            ),
            _Drop<int>(
              keyName: 'min-ok',
              label: 'Lowest comfortable value',
              revision: c.revision * 100 + c.scaleMax,
              value: c.minOk,
              enabled: !ro,
              width: 220,
              items: {for (var v = 1; v <= c.scaleMax; v++) v: '$v'},
              onChanged: (v) => c.edit(() => c.minOk = v),
            ),
          ]),
          const SizedBox(height: 12),
          for (var i = 0; i < c.scaleMax; i++) ...[
            _Text(
              keyName: 'label-${i + 1}',
              label: 'Label for ${i + 1}',
              revision: c.revision * 100 + c.scaleMax,
              value: c.labels[i],
              enabled: !ro,
              onChanged: (v) => c.setLabel(i, v),
            ),
            const SizedBox(height: 8),
          ],
          _Switch(
            keyName: 'ask-every-stage',
            title: 'Ask the comfort question after every stage',
            value: c.askEveryStage,
            enabled: !ro,
            onChanged: (v) => c.edit(() => c.askEveryStage = v),
          ),
        ]),
        const SizedBox(height: 12),
        _Section(title: 'Progression', children: [
          _Text(
            keyName: 'hold-invalid',
            label: 'Repeat a stage when more than this share of samples is unusable',
            revision: c.revision,
            value: c.holdInvalid,
            enabled: !ro,
            width: 360,
            number: true,
            onChanged: (v) => c.edit(() => c.holdInvalid = v),
          ),
          const SizedBox(height: 8),
          _Switch(
            keyName: 'easier-on-low',
            title: 'Go back one stage when comfort is below the lowest comfortable value',
            value: c.easierOnLowComfort,
            enabled: !ro,
            onChanged: (v) => c.edit(() => c.easierOnLowComfort = v),
          ),
          _Switch(
            keyName: 'stop-on-two-low',
            title: 'Stop after two low comfort answers in a row',
            value: c.stopOnTwoLow,
            enabled: !ro,
            onChanged: (v) => c.edit(() => c.stopOnTwoLow = v),
          ),
        ]),
        const SizedBox(height: 12),
        if (gradual) _GradualSection(controller: c) else _InterestSection(controller: c),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (!ro) ...[
            FilledButton(
              key: const Key('save-draft'),
              onPressed: c.busy ? null : c.save,
              child: Text(c.busy ? 'Working...' : 'Save draft'),
            ),
            OutlinedButton(
              key: const Key('publish'),
              onPressed: c.busy ? null : onPublish,
              child: const Text('Publish'),
            ),
          ],
          if (c.isPublished && c.canEdit)
            FilledButton(
              key: const Key('new-draft'),
              onPressed: c.busy ? null : c.newDraft,
              child: const Text('New draft from published'),
            ),
        ]),
      ],
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.controller});

  final ProtocolEditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final published = c.isPublished;
    return Container(
      key: const Key('protocol-status'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: published ? AppColors.successTint : AppColors.warningTint,
        borderRadius: BorderRadius.circular(kRadius),
      ),
      child: Text(
        published
            ? 'Published, version ${c.version}'
            : (c.isNew ? 'Draft, not saved yet' : 'Draft'),
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

class _GradualSection extends StatelessWidget {
  const _GradualSection({required this.controller});

  final ProtocolEditorController controller;

  static const _levels = {
    0: '0 · Plain square',
    1: '1 · Face-like shape',
    2: '2 · Low-detail face',
    3: '3 · Real face',
  };

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final ro = c.readOnly;
    return _Section(title: 'Stages (gradual face)', children: [
      for (var i = 0; i < c.stages.length; i++) ...[
        _StageRow(controller: c, index: i, stage: c.stages[i]),
        const SizedBox(height: 8),
      ],
      if (!ro)
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('add-stage'),
            onPressed: c.addStage,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add stage'),
          ),
        ),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 12, children: [
        _Drop<NumberZone>(
          keyName: 'final-zone-limit',
          label: 'Furthest zone a number may reach',
          revision: c.revision,
          value: c.finalZoneLimit,
          enabled: !ro,
          width: 280,
          items: {for (final z in NumberZone.values) z: z.label},
          onChanged: (v) => c.edit(() => c.finalZoneLimit = v),
        ),
      ]),
      const SizedBox(height: 8),
      _Switch(
        keyName: 'allow-simultaneous',
        title: 'Allow the face and the number zone to change in the same stage',
        value: c.allowSimultaneous,
        enabled: !ro,
        onChanged: (v) => c.edit(() => c.allowSimultaneous = v),
      ),
      const SizedBox(height: 8),
      _Text(
        keyName: 'real-face-url',
        label: 'Real face image URL (face level 3, optional)',
        revision: c.revision,
        value: c.realFaceUrl,
        enabled: !ro,
        onChanged: (v) => c.edit(() => c.realFaceUrl = v),
      ),
    ]);
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.controller,
    required this.index,
    required this.stage,
  });

  final ProtocolEditorController controller;
  final int index;
  final StageDraft stage;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final ro = c.readOnly;
    final k = 'stage-$index';
    final rev = c.revision * 1000 + stage.uid;
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
                child: Text('Stage ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              if (!ro)
                IconButton(
                  key: Key('$k-remove'),
                  tooltip: 'Remove stage',
                  onPressed: c.stages.length > 1
                      ? () => c.removeStage(stage.uid)
                      : null,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _Drop<int>(
              keyName: '$k-level',
              label: 'Face level',
              revision: rev,
              value: stage.faceLevel,
              enabled: !ro,
              width: 200,
              items: _GradualSection._levels,
              onChanged: (v) => c.edit(() => stage.faceLevel = v),
            ),
            _Drop<NumberZone>(
              keyName: '$k-zone',
              label: 'Number zone',
              revision: rev,
              value: stage.zone,
              enabled: !ro,
              width: 200,
              items: {for (final z in NumberZone.values) z: z.label},
              onChanged: (v) => c.edit(() => stage.zone = v),
            ),
            _Text(
              keyName: '$k-trials',
              label: 'Trials',
              revision: rev,
              value: stage.trials,
              enabled: !ro,
              width: 100,
              number: true,
              onChanged: (v) => c.edit(() => stage.trials = v),
            ),
            _Text(
              keyName: '$k-min-correct',
              label: 'Min correct (0-1)',
              revision: rev,
              value: stage.minCorrect,
              enabled: !ro,
              width: 140,
              number: true,
              onChanged: (v) => c.edit(() => stage.minCorrect = v),
            ),
            _Drop<StageResponseMode>(
              keyName: '$k-mode',
              label: 'Response mode',
              revision: rev,
              value: stage.mode,
              enabled: !ro,
              width: 200,
              items: {for (final m in StageResponseMode.values) m: m.label},
              onChanged: (v) => c.edit(() => stage.mode = v),
            ),
            _Text(
              keyName: '$k-seconds',
              label: 'Seconds per number',
              revision: rev,
              value: stage.trialSeconds,
              enabled: !ro,
              width: 160,
              number: true,
              onChanged: (v) => c.edit(() => stage.trialSeconds = v),
            ),
          ]),
        ],
      ),
    );
  }
}

class _InterestSection extends StatelessWidget {
  const _InterestSection({required this.controller});

  final ProtocolEditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return _Section(title: 'Interest conversation', children: [
      _Text(
        keyName: 'interaction-points',
        label: 'Interaction points',
        revision: c.revision,
        value: c.interactionPoints,
        enabled: !c.readOnly,
        width: 200,
        number: true,
        onChanged: (v) => c.edit(() => c.interactionPoints = v),
      ),
      const SizedBox(height: 4),
      Text(
        'How many times the conversation asks the participant to choose. '
        'The content item supplies the video and the questions.',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ]);
  }
}

// ------------------------------------------------------------- building blocks

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

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

/// A text box that starts from [value] and starts over when [revision] changes.
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
  });

  final String keyName;
  final String label;
  final int revision;
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final double? width;
  final bool number;

  @override
  Widget build(BuildContext context) {
    final field = KeyedSubtree(
      key: ValueKey('$keyName-$revision'),
      child: TextFormField(
        key: Key(keyName),
        initialValue: value,
        enabled: enabled,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(labelText: label),
        onChanged: onChanged,
      ),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }
}

class _Drop<T> extends StatelessWidget {
  const _Drop({
    required this.keyName,
    required this.label,
    required this.revision,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
    this.width,
  });

  final String keyName;
  final String label;
  final int revision;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final bool enabled;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final field = KeyedSubtree(
      key: ValueKey('$keyName-$revision'),
      child: DropdownButtonFormField<T>(
        key: Key(keyName),
        initialValue: items.containsKey(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final e in items.entries)
            DropdownMenuItem<T>(value: e.key, child: Text(e.value)),
        ],
        onChanged: enabled ? (v) => v == null ? null : onChanged(v) : null,
      ),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.keyName,
    required this.title,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String keyName;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        key: Key(keyName),
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        value: value,
        onChanged: enabled ? onChanged : null,
      );
}
