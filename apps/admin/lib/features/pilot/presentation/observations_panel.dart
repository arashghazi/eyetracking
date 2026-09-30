import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../ai/presentation/ai_widgets.dart' show MutedText, StateChip;
import '../application/observations_controller.dart';
import 'pilot_widgets.dart';

/// The observations of one session, with their own controller: loads the
/// list when it appears. Researchers also get the form. Give it a key that
/// includes the session id so a new session starts a new list.
class SessionObservations extends StatefulWidget {
  const SessionObservations({
    super.key,
    required this.studyId,
    required this.sessionId,
    required this.canEdit,
    this.sessionTimeMs,
  });

  final int studyId;
  final String sessionId;
  final bool canEdit;
  final int? Function()? sessionTimeMs;

  @override
  State<SessionObservations> createState() => _SessionObservationsState();
}

class _SessionObservationsState extends State<SessionObservations> {
  late final ObservationsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ObservationsController(
      AppScope.read(context).pilot,
      widget.studyId,
      widget.sessionId,
    )..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ObservationsPanel(
        controller: _controller,
        canEdit: widget.canEdit,
        sessionTimeMs: widget.sessionTimeMs,
      );
}

/// A supervisor's notes on one session: the list, and for researchers the form
/// that adds one. Used next to the live monitor and on the session detail.
///
/// [sessionTimeMs] (the live monitor passes the newest sample time) adds the
/// "Use current session time" option; without it a note is about the session
/// as a whole.
class ObservationsPanel extends StatefulWidget {
  const ObservationsPanel({
    super.key,
    required this.controller,
    required this.canEdit,
    this.sessionTimeMs,
  });

  final ObservationsController controller;
  final bool canEdit;

  /// The session time a note may be tied to, or null when there is none.
  final int? Function()? sessionTimeMs;

  @override
  State<ObservationsPanel> createState() => _ObservationsPanelState();
}

class _ObservationsPanelState extends State<ObservationsPanel> {
  final _text = TextEditingController();
  String _category = ObservationCategory.comfort;
  String _severity = ObservationSeverity.info;
  bool _useTime = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final now = widget.sessionTimeMs?.call();
    final ok = await widget.controller.add(
      category: _category,
      severity: _severity,
      text: _text.text,
      tMs: _useTime ? now : null,
    );
    if (ok && mounted) _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final now = widget.sessionTimeMs?.call();
        return Card(
          key: const Key('observations-panel'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.loadedOnce ? 'Observations (${c.items.length})' : 'Observations',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const MutedText(
                  'Notes under the research code. They cannot be edited or '
                  'deleted; write a new one to correct.',
                ),
                if (widget.canEdit) ...[
                  const SizedBox(height: 12),
                  _form(context, c, now),
                ],
                const SizedBox(height: 12),
                _list(context, c),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _form(BuildContext context, ObservationsController c, int? now) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            WrapItem(
              width: 180,
              child: DropdownButtonFormField<String>(
                key: const Key('obs-category'),
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final v in ObservationCategory.all)
                    DropdownMenuItem(
                      value: v,
                      child: Text(observationCategoryLabel(v)),
                    ),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
            ),
            WrapItem(
              width: 140,
              child: DropdownButtonFormField<String>(
                key: const Key('obs-severity'),
                initialValue: _severity,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Severity'),
                items: [
                  for (final v in ObservationSeverity.all)
                    DropdownMenuItem(
                      value: v,
                      child: Text(observationSeverityLabel(v)),
                    ),
                ],
                onChanged: (v) => setState(() => _severity = v ?? _severity),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('obs-text'),
          controller: _text,
          minLines: 2,
          maxLines: 5,
          maxLength: kMaxObservationChars,
          decoration: const InputDecoration(
            labelText: 'What did you see?',
            helperText: 'Do not write names or identifying details.',
          ),
          onChanged: (_) {
            if (c.formError != null) c.dismissFormError();
          },
        ),
        if (widget.sessionTimeMs != null)
          CheckboxListTile(
            key: const Key('obs-use-time'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Use current session time'),
            subtitle: Text(
              now == null
                  ? 'No samples yet, so there is no session time.'
                  : 'Now at ${formatClockMs(now)} in the session.',
            ),
            value: _useTime && now != null,
            onChanged: now == null
                ? null
                : (v) => setState(() => _useTime = v ?? false),
          ),
        if (c.formError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: MessageBanner(
              key: const Key('obs-form-error'),
              message: c.formError!,
              onDismiss: c.dismissFormError,
            ),
          )
        else if (c.notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: MessageBanner(
              key: const Key('obs-notice'),
              kind: BannerKind.success,
              message: c.notice!,
            ),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const Key('obs-save'),
            onPressed: c.saving ? null : _save,
            child: Text(c.saving ? 'Saving...' : 'Save'),
          ),
        ),
      ],
    );
  }

  Widget _list(BuildContext context, ObservationsController c) {
    if (c.error != null) {
      return MessageBanner(key: const Key('obs-error'), message: c.error!);
    }
    if (c.loading && !c.loadedOnce) return const BusyBox();
    if (c.items.isEmpty) {
      return const EmptyNote('No observations for this session yet.');
    }
    return Column(
      key: const Key('obs-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < c.items.length; i++) ...[
          if (i > 0) const Divider(height: 16),
          ObservationTile(observation: c.items[i]),
        ],
      ],
    );
  }
}

/// One observation: severity, category, session time, the text and when it
/// was written.
class ObservationTile extends StatelessWidget {
  const ObservationTile({super.key, required this.observation, this.showCode = false});

  final Observation observation;

  /// The report lists observations of many sessions and names the code.
  final bool showCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = observation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (showCode && o.participantCode != null) CodeText(o.participantCode!),
            SeverityChip(severity: o.severity),
            Text(
              observationCategoryLabel(o.category),
              style: theme.textTheme.labelLarge,
            ),
            Text(
              o.tMs == null ? 'Whole session' : 'at ${formatClockMs(o.tMs!)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            Text(
              formatTimestamp(o.createdAt),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 2),
        SelectableText(o.text),
      ],
    );
  }
}

/// info grey, minor blue, major amber, stop red; always with the word.
class SeverityChip extends StatelessWidget {
  const SeverityChip({super.key, required this.severity});

  final String severity;

  @override
  Widget build(BuildContext context) {
    final label = observationSeverityLabel(severity);
    return switch (severity) {
      ObservationSeverity.stop => StateChip(
          label: label,
          foreground: AppColors.error,
          background: AppColors.errorTint,
          icon: Icons.stop_circle_outlined,
        ),
      ObservationSeverity.major => StateChip(
          label: label,
          foreground: AppColors.warning,
          background: AppColors.warningTint,
          icon: Icons.priority_high,
        ),
      ObservationSeverity.minor => StateChip(
          label: label,
          foreground: AppColors.tealDark,
          background: AppColors.tealTint,
        ),
      _ => StateChip(label: label, foreground: AppColors.textMuted, outlined: true),
    };
  }
}
