import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../application/data_export_controller.dart';

/// "Download my data": what the service stores about the participant, in
/// numbers, and the whole of it as a JSON file.
class DataExportScreen extends StatefulWidget {
  const DataExportScreen({super.key});

  @override
  State<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends State<DataExportScreen> {
  late final DataExportController _controller;

  @override
  void initState() {
    super.initState();
    final deps = AppScope.read(context);
    _controller = DataExportController(deps.dataExport, deps.saveFile)..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Download my data')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final c = _controller;
          final counts = c.counts;
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
              Text(
                'This is all the data we hold about you, exactly as stored.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              if (counts == null)
                c.loading
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton(
                          key: const Key('reload-data'),
                          onPressed: c.load,
                          child: const Text('Try again'),
                        ),
                      )
              else ...[
                _Counts(counts: counts),
                const SizedBox(height: 12),
                const _RawDataNote(),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const Key('download-json'),
                      onPressed: c.downloading ? null : c.download,
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: Text(c.downloading ? 'Preparing...' : 'Download JSON'),
                    ),
                    OutlinedButton(
                      key: const Key('reload-data'),
                      onPressed: c.loading ? null : c.load,
                      child: const Text('Reload'),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Counts extends StatelessWidget {
  const _Counts({required this.counts});

  final MyDataCounts counts;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Sessions', counts.sessions, 'count-sessions'),
      ('Gaze samples', counts.samples, 'count-samples'),
      ('Session events', counts.events, 'count-events'),
      ('Consents', counts.consents, 'count-consents'),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 560 ? 4 : 2;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final (label, value, key) in items)
            SizedBox(
              width: width,
              child: Card(
                key: Key(key),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$value',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _RawDataNote extends StatelessWidget {
  const _RawDataNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('raw-data-note'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'The gaze numbers and the session events are the raw data. '
                'No camera video exists: the camera image is processed in '
                'memory and is never stored.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
