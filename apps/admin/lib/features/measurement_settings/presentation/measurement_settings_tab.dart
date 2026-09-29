import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../application/measurement_settings_controller.dart';

/// The thresholds a study uses for calibration and regional validation.
/// Researchers edit them; analysts see the same form read-only.
class MeasurementSettingsTab extends StatefulWidget {
  const MeasurementSettingsTab({
    super.key,
    required this.studyId,
    required this.canEdit,
  });

  final int studyId;
  final bool canEdit;

  @override
  State<MeasurementSettingsTab> createState() => _MeasurementSettingsTabState();
}

class _MeasurementSettingsTabState extends State<MeasurementSettingsTab>
    with AutomaticKeepAliveClientMixin {
  late final MeasurementSettingsController _controller;
  final Map<String, TextEditingController> _fields = {};

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
            Text('Measurement settings', style: theme.textTheme.titleLarge),
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
                          onPressed: c.saving ? null : c.save,
                          child: Text(c.saving ? 'Saving...' : 'Save'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
