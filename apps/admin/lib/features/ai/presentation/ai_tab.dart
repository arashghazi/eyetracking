import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../content/presentation/content_editor_screen.dart';
import '../../live/application/live_avatar_controller.dart';
import '../../live/presentation/live_avatar_card.dart';
import '../application/ai_controller.dart';
import 'ai_status_card.dart';
import 'jobs_table.dart';
import 'text_job_card.dart';

/// The AI tab: what is configured, the cost cap, the text-job form and the
/// jobs table. Provider keys stay on the server.
class AiTab extends StatefulWidget {
  const AiTab({
    super.key,
    required this.studyId,
    required this.isAdmin,
    required this.canEdit,
    this.tabIndex,
  });

  final int studyId;

  /// Administrators change the cost cap.
  final bool isAdmin;

  /// Researchers (and administrators) create, cancel and retry jobs;
  /// analysts only read.
  final bool canEdit;

  /// Position of this tab in the study screen; the jobs are read again when
  /// the tab comes back into view.
  final int? tabIndex;

  @override
  State<AiTab> createState() => _AiTabState();
}

class _AiTabState extends State<AiTab> with AutomaticKeepAliveClientMixin {
  late final AiController _controller;
  late final LiveAvatarController _live;
  AiBudget? _shownBudget;
  TabController? _tabs;
  bool _visible = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final deps = AppScope.read(context);
    _controller = AiController(
      deps.ai,
      widget.studyId,
      content: deps.content,
      schedule: deps.schedule,
    )..load();
    _live = LiveAvatarController(deps.live, widget.studyId)..load();
    _controller.addListener(_onBudgetChanged);
  }

  /// The cap is shared with the live replies: when it changes, the live card
  /// reads its numbers again.
  void _onBudgetChanged() {
    final saved = _controller.savedBudget;
    if (saved != null && !identical(saved, _shownBudget)) {
      _shownBudget = saved;
      _live.load();
    }
  }

  void _reload() {
    _controller.load();
    _live.load();
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
      _live.load();
    }
    _visible = visible;
  }

  @override
  void dispose() {
    _tabs?.removeListener(_onTab);
    _controller.removeListener(_onBudgetChanged);
    _controller.dispose();
    _live.dispose();
    super.dispose();
  }

  Future<void> _openContent(String contentId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ContentEditorScreen(
          studyId: widget.studyId,
          canEdit: widget.canEdit,
          contentId: contentId,
        ),
      ),
    );
    if (mounted) await _controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        final run = c.lastRun;
        return PageFrame(
          maxWidth: 1200,
          buildAll: true,
          banner: c.error != null
              ? MessageBanner(
                  key: const Key('ai-error'),
                  message: c.error!,
                  onDismiss: c.dismissError,
                )
              : run != null
                  ? MessageBanner(
                      key: const Key('run-result'),
                      kind: BannerKind.success,
                      message: 'Processed ${run.processed} '
                          '${run.processed == 1 ? 'job' : 'jobs'}: '
                          '${run.succeeded} succeeded, ${run.failed} failed.',
                      onDismiss: c.dismissNotice,
                    )
                  : c.notice != null
                      ? MessageBanner(
                          key: const Key('ai-notice'),
                          kind: BannerKind.success,
                          message: c.notice!,
                          onDismiss: c.dismissNotice,
                        )
                      : null,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('AI content', style: theme.textTheme.titleLarge),
                OutlinedButton.icon(
                  key: const Key('refresh-jobs'),
                  onPressed: c.loading ? null : _reload,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                ),
                if (widget.canEdit)
                  FilledButton.icon(
                    key: const Key('run-jobs'),
                    onPressed: c.busy ? null : c.runQueued,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Run queued jobs now'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Drafts written or filmed by AI. Every text needs a researcher '
              'review before videos are made, and nothing reaches a '
              'participant without approval.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            AiStatusCard(controller: c, isAdmin: widget.isAdmin),
            const SizedBox(height: 12),
            LiveAvatarCard(controller: _live),
            if (widget.canEdit) ...[
              const SizedBox(height: 12),
              TextJobCard(
                studyId: widget.studyId,
                sendFreeText: c.status?.sendFreeText ?? false,
                onCreated: (job) => c.addJobs([job]),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Jobs', style: theme.textTheme.titleMedium),
                if (c.autoRefreshing)
                  Text(
                    'Refreshing every ${c.pollInterval.inSeconds} s while a '
                    'job is queued or running.',
                    key: const Key('auto-refresh-note'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (c.loading && !c.loadedOnce)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              JobsTable(
                controller: c,
                canEdit: widget.canEdit,
                onOpenContent: _openContent,
              ),
          ],
        );
      },
    );
  }
}
