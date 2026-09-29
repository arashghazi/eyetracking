import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_scope.dart';
import '../application/demographics_controller.dart';

class DemographicsScreen extends StatefulWidget {
  const DemographicsScreen({super.key});

  @override
  State<DemographicsScreen> createState() => _DemographicsScreenState();
}

class _DemographicsScreenState extends State<DemographicsScreen> {
  late final DemographicsController _controller;
  final Map<String, TextEditingController> _texts = {};

  @override
  void initState() {
    super.initState();
    _controller = DemographicsController(AppScope.read(context).demographics);
    _controller.addListener(_syncTexts);
    _controller.load();
  }

  /// Creates a text controller per text/number field once the form is loaded,
  /// seeded with any saved answer.
  void _syncTexts() {
    final form = _controller.form;
    if (form == null) return;
    for (final f in form.fields) {
      if (f.type != DemographicsFieldType.text &&
          f.type != DemographicsFieldType.number) {
        continue;
      }
      _texts.putIfAbsent(
        f.key,
        () => TextEditingController(
          text: _controller.valueOf(f.key) as String? ?? '',
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final t in _texts.values) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Demographics')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final c = _controller;
          final form = c.form;
          if (c.loading && form == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return PageFrame(
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
              if (form == null)
                _NoForm(failed: c.error != null, onReload: c.load)
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fields marked * are required.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        for (final f in form.fields) ...[
                          const SizedBox(height: 16),
                          _FieldView(
                            field: f,
                            controller: c,
                            text: _texts[f.key],
                          ),
                        ],
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton(
                            key: const Key('demographics-submit'),
                            onPressed: c.saving ? null : c.submit,
                            child: Text(c.saving ? 'Saving...' : 'Save answers'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NoForm extends StatelessWidget {
  const _NoForm({required this.failed, required this.onReload});

  final bool failed;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failed
                  ? 'The form could not be loaded.'
                  : 'There are no demographics questions yet.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(failed
                ? 'Please try again.'
                : 'The research team has not published a form. Please come back later.'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onReload, child: const Text('Reload')),
          ],
        ),
      ),
    );
  }
}

class _FieldView extends StatelessWidget {
  const _FieldView({
    required this.field,
    required this.controller,
    required this.text,
  });

  final DemographicsField field;
  final DemographicsController controller;
  final TextEditingController? text;

  @override
  Widget build(BuildContext context) {
    final label = field.required ? '${field.label} *' : field.label;
    final error = controller.errors[field.key];
    final key = Key('field-${field.key}');

    switch (field.type) {
      case DemographicsFieldType.number:
        return TextField(
          key: key,
          controller: text,
          decoration: InputDecoration(labelText: label, errorText: error),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))],
          textInputAction: TextInputAction.next,
          onChanged: (v) => controller.setValue(field.key, v),
        );
      case DemographicsFieldType.text:
        return TextField(
          key: key,
          controller: text,
          decoration: InputDecoration(labelText: label, errorText: error),
          textInputAction: TextInputAction.next,
          onChanged: (v) => controller.setValue(field.key, v),
        );
      case DemographicsFieldType.choice:
        return DropdownButtonFormField<String>(
          key: key,
          initialValue: controller.valueOf(field.key) as String?,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, errorText: error),
          items: [
            for (final o in field.options)
              DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: (v) => controller.setValue(field.key, v),
        );
      case DemographicsFieldType.boolean:
        return SwitchListTile(
          key: key,
          value: controller.valueOf(field.key) == true,
          onChanged: (v) => controller.setValue(field.key, v),
          contentPadding: EdgeInsets.zero,
          title: Text(label),
        );
    }
  }
}
