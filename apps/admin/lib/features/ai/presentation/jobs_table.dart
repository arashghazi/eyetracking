import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../application/ai_controller.dart';
import 'ai_widgets.dart';

/// The jobs of the study, newest first. Researchers can cancel a queued job,
/// retry a failed one and open the content a job works on.
class JobsTable extends StatelessWidget {
  const JobsTable({
    super.key,
    required this.controller,
    required this.canEdit,
    required this.onOpenContent,
  });

  final AiController controller;
  final bool canEdit;
  final void Function(String contentId) onOpenContent;

  @override
  Widget build(BuildContext context) {
    final jobs = controller.jobs;
    if (jobs.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            controller.loadedOnce
                ? 'No AI jobs yet.'
                : 'The jobs could not be loaded.',
            key: const Key('no-jobs'),
          ),
        ),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              key: const Key('jobs-table'),
              columnSpacing: 14,
              horizontalMargin: 12,
              dataRowMinHeight: 48,
              dataRowMaxHeight: double.infinity,
              columns: const [
                DataColumn(label: Text('Kind')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Provider')),
                DataColumn(label: Text('Content')),
                DataColumn(label: Text('Segment')),
                DataColumn(label: Text('Attempts')),
                DataColumn(label: Text('Cost est. / actual')),
                DataColumn(label: Text('Created')),
                DataColumn(label: Text('Error')),
                DataColumn(label: Text('')),
              ],
              rows: [
                for (final job in jobs)
                  DataRow(
                    key: ValueKey('job-row-${job.id}'),
                    cells: [
                      DataCell(Text(
                        job.kind == AiJobKind.video ? 'Video' : 'Text',
                        key: Key('job-kind-${job.id}'),
                      )),
                      DataCell(KeyedSubtree(
                        key: Key('job-status-${job.id}'),
                        child: JobStatusChip(status: job.status),
                      )),
                      DataCell(Text(job.provider.isEmpty ? '-' : job.provider)),
                      DataCell(_ContentCell(
                        job: job,
                        title: controller.contentTitle(job.contentId),
                      )),
                      DataCell(Text(job.segmentId ?? '-')),
                      DataCell(Text('${job.attempts} / ${job.maxAttempts}')),
                      DataCell(Text(
                        '${formatUnits(job.costEstimateUnits)} / '
                        '${formatUnits(job.costActualUnits)}',
                        key: Key('job-cost-${job.id}'),
                      )),
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 96),
                        child: Text(formatTimestamp(job.createdAt)),
                      )),
                      DataCell(_ErrorCell(job: job)),
                      DataCell(_Actions(
                        job: job,
                        canEdit: canEdit,
                        busy: controller.busy,
                        controller: controller,
                        onOpenContent: onOpenContent,
                      )),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContentCell extends StatelessWidget {
  const _ContentCell({required this.job, required this.title});

  final AiJob job;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final id = job.contentId;
    if (id == null) return const Text('-');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 170),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Text(title!, maxLines: 2, overflow: TextOverflow.ellipsis),
          Text(
            '#$id',
            key: Key('job-content-${job.id}'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

/// The error, shortened with a tooltip; tapping it shows all of it.
class _ErrorCell extends StatefulWidget {
  const _ErrorCell({required this.job});

  final AiJob job;

  @override
  State<_ErrorCell> createState() => _ErrorCellState();
}

class _ErrorCellState extends State<_ErrorCell> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final error = widget.job.error;
    if (error == null) return const Text('-');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: Tooltip(
        message: error,
        waitDuration: const Duration(milliseconds: 300),
        child: InkWell(
          key: Key('job-error-${widget.job.id}'),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    error,
                    key: Key('job-error-text-${widget.job.id}'),
                    maxLines: _expanded ? null : 2,
                    overflow:
                        _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: AppColors.error,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.job,
    required this.canEdit,
    required this.busy,
    required this.controller,
    required this.onOpenContent,
  });

  final AiJob job;
  final bool canEdit;
  final bool busy;
  final AiController controller;
  final void Function(String contentId) onOpenContent;

  @override
  Widget build(BuildContext context) {
    final contentId = job.contentId;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canEdit && job.canCancel)
          TextButton(
            key: Key('job-cancel-${job.id}'),
            onPressed: busy ? null : () => controller.cancel(job),
            child: const Text('Cancel'),
          ),
        if (canEdit && job.canRetry)
          TextButton(
            key: Key('job-retry-${job.id}'),
            onPressed: busy ? null : () => controller.retry(job),
            child: const Text('Retry'),
          ),
        if (contentId != null)
          TextButton(
            key: Key('job-open-${job.id}'),
            onPressed: () => onOpenContent(contentId),
            child: const Text('Open content'),
          ),
      ],
    );
  }
}
