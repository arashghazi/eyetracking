import 'dart:async';

import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../pilot/application/settings_history_controller.dart';
import '../../pilot/presentation/settings_history_card.dart';
import '../application/measurement_settings_controller.dart';

/// The thresholds a study uses for calibration and regional validation.
/// Researchers edit them; analysts see the same form read-only. Every real
/// change is a new settings version; saving asks for an optional rationale and
/// the history of versions is one button away.
class MeasurementSettingsTab extends StatefulWidget {
  const MeasurementSettingsTab({
    super.key,
    required this.studyId,
    required this.canEdit,
    this.tabIndex,
  });

  final int studyId;
  final bool canEdit;

  /// Position of this tab in the study screen; the settings are read again
  /// when the tab comes back into view (a threshold review may have saved a
  /// new version meanwhile).
  final int? tabIndex;

  @override
  State<MeasurementSettingsTab> createState() => _MeasurementSettingsTabState();
}

class _MeasurementSettingsTabState extends State<MeasurementSettingsTab>
    with AutomaticKeepAliveClientMixin {
  late final MeasurementSettingsController _controller;
  final Map<String, TextEditingController> _fields = {};
  SettingsHistoryController? _history;
  bool _showHistory = false;
  TabController? _tabs;
  bool _visible = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = MeasurementSettingsController(
      AppScope.read(context).measurementSettings,
      widget.studyId,
      canEdit: widget.canEdit,
    )..addListener(_syncFields);
    _controller.load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabs = DefaultTabController.maybeOf(context);
    if (tabs != _tabs) {
      _tabs?.removeListener(_onTab);
      _tabs = tabs;
      _visible = tabs != null && tabs.index == widget.tabIndex;
      tabs?.addListener(_onTab);
    }
  }

  void _onTab() {
    final tabs = _tabs;
    if (tabs == null || tabs.indexIsChanging) return;
    final visible = tabs.index == widget.tabIndex;
    if (visible && !_visible) {
      _controller.refresh();
      if (_showHistory) _history?.load();
    }
    _visible = visible;
  }

  void _toggleHistory() {
    setState(() {
      _showHistory = !_showHistory;
      if (_showHistory && _history == null) {
        _history = SettingsHistoryController(
          AppScope.read(context).pilot,
          widget.studyId,
        )..load();
      }
    });
  }

  /// Asks for the optional rationale, then saves. An invalid form is not
  /// sent: the controller shows what to fix.
  Future<void> _save() async {
    final c = _controller;
    if (!c.validate()) {
      await c.save();
      return;
    }
    final rationale = await showDialog<String>(
      context: context,
      builder: (_) => _RationaleDialog(version: c.version),
    );
    if (rationale == null) return;
    final saved = await c.save(rationale: rationale);
    if (saved && _showHistory) unawaited(_history?.load());
  }

  /// Keeps the text boxes in step with a load or a saved value.
  void _syncFields() {
    for (final f in MeasurementSettingsController.fields) {
      final box = _fields.putIfAbsent(f.key, TextEditingController.new);
      final wanted = _controller.text(f.key);
      if (box.text != wanted) {
        box.value = TextEditingValue(
          text: wanted,
          selection: TextSelection.collapsed(offset: wanted.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabs?.removeListener(_onTab);
    _history?.dispose();
    _controller
      ..removeListener(_syncFields)
      ..dispose();
    for (final f in _fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        return PageFrame(
          maxWidth: 720,
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
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Measurement settings', style: theme.textTheme.titleLarge),
                if (c.loaded)
                  Text(
                    'Version ${c.version}',
                    key: const Key('settings-version'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                OutlinedButton.icon(
                  key: const Key('settings-history-toggle'),
                  onPressed: _toggleHistory,
                  icon: const Icon(Icons.history, size: 18),
                  label: Text(_showHistory ? 'Hide history' : 'History'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'These thresholds decide when a calibration is accepted and when '
              'the regional validation passes for this study.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (c.loading && !c.loaded)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!c.loaded)
              OutlinedButton(onPressed: c.load, child: const Text('Try again'))
            else ...[
              if (!widget.canEdit) ...[
                const MessageBanner(
                  key: Key('settings-read-only'),
                  kind: BannerKind.info,
                  message: 'You have read-only access. Researchers of this '
                      'study can change these settings.',
                ),
                const SizedBox(height: 12),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final f in MeasurementSettingsController.fields) ...[
                        TextField(
                          key: Key('setting-${f.key}'),
                          controller: _fields[f.key],
                          enabled: widget.canEdit,
                          keyboardType: TextInputType.numberWithOptions(
                            decimal: !f.integer,
                          ),
                          decoration: InputDecoration(
                            labelText: f.label,
                            helperText: f.help,
                            helperMaxLines: 2,
                            errorText: c.errorFor(f.key),
                            errorMaxLines: 2,
                          ),
                          onChanged: (v) => c.setText(f.key, v),
                        ),
                        const SizedBox(height: 16),
                      ],
                      SwitchListTile(
                        key: const Key('setting-allow_continue_without_validation'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Allow continuing without validation'),
                        subtitle: const Text(
                          'Participants whose validation fails may go on; '
                          'their eye-region attention is then not evaluable.',
                        ),
                        value: c.allowContinueWithoutValidation,
                        onChanged: widget.canEdit ? c.setAllowContinue : null,
                      ),
                      if (widget.canEdit) ...[
                        const SizedBox(height: 12),
                        FilledButton(
                          key: const Key('save-settings'),
                          onPressed: c.saving ? null : _save,
                          child: Text(c.saving ? 'Saving...' : 'Save'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            if (_showHistory && _history != null) ...[
              const SizedBox(height: 12),
              SettingsHistoryCard(controller: _history!),
            ],
          ],
        );
      },
    );
  }
}

/// Asks why the settings change. The rationale is optional: cancelling the
/// dialog does not save, an empty rationale does.
class _RationaleDialog extends StatefulWidget {
  const _RationaleDialog({required this.version});

  final int version;

  @override
  State<_RationaleDialog> createState() => _RationaleDialogState();
}

class _RationaleDialogState extends State<_RationaleDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('settings-rationale-dialog'),
        title: const Text('Save the settings'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A real change creates version ${widget.version + 1}. Saying '
                'why helps the team later; it is kept with the version and '
                'your account.',
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('settings-rationale'),
                controller: _text,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                maxLength: MeasurementSettingsController.maxRationaleChars,
                decoration: const InputDecoration(
                  labelText: 'Rationale (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('settings-rationale-cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('settings-rationale-confirm'),
            onPressed: () => Navigator.of(context).pop(_text.text.trim()),
            child: const Text('Save'),
          ),
        ],
      );
}
