import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_scope.dart';
import '../application/data_export_controller.dart';

class DataExportScreen extends StatefulWidget {
  const DataExportScreen({super.key});

  @override
  State<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends State<DataExportScreen> {
  late final DataExportController _controller;
  String? _copied;

  @override
  void initState() {
    super.initState();
    _controller = DataExportController(AppScope.read(context).dataExport)
      ..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _copied = 'Copied to the clipboard.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My data')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final c = _controller;
          if (c.loading && c.json == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (c.error != null) ...[
                      MessageBanner(message: c.error!, onDismiss: c.dismissError),
                      const SizedBox(height: 12),
                    ],
                    if (_copied != null) ...[
                      MessageBanner(
                        message: _copied!,
                        kind: BannerKind.success,
                        onDismiss: () => setState(() => _copied = null),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      'This is all the data we hold about you, exactly as stored.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: c.loading ? null : c.load,
                          child: const Text('Reload'),
                        ),
                        if (c.json != null)
                          OutlinedButton(
                            key: const Key('copy-data'),
                            onPressed: () => _copy(c.json!),
                            child: const Text('Copy'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (c.json != null)
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(kRadius),
                          ),
                          child: Scrollbar(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(12),
                              child: SelectableText(
                                c.json!,
                                key: const Key('data-json'),
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontFamilyFallback: kMonospaceFallback,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
