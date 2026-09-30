import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../application/live_monitor_controller.dart';
import 'live_panel.dart';
import 'observations_panel.dart';
import 'pilot_widgets.dart';

/// Live: the sessions running now, and for the one picked a status panel that
/// polls every 2.5 s with the observation form next to it. Researchers only;
/// the server refuses everyone else.
class LiveSection extends StatefulWidget {
  const LiveSection({
    super.key,
    required this.studyId,
    required this.canEdit,
    this.visible = true,
  });

  final int studyId;

  /// Researchers monitor and write observations; analysts do not have access
  /// to the live monitor.
  final bool canEdit;

  /// False while the Pilot tab is not on screen: polling pauses.
  final bool visible;

  @override
  State<LiveSection> createState() => _LiveSectionState();
}

class _LiveSectionState extends State<LiveSection> {
  late final LiveMonitorController _controller;

  @override
  void initState() {
    super.initState();
    final deps = AppScope.read(context);
    _controller = LiveMonitorController(
      deps.pilot,
      widget.studyId,
      schedule: deps.schedule,
    );
    if (widget.canEdit) _controller.loadActive();
  }

  @override
  void didUpdateWidget(LiveSection old) {
    super.didUpdateWidget(old);
    if (old.visible != widget.visible) {
      widget.visible ? _controller.resume() : _controller.suspend();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!widget.canEdit) {
      return const Card(
        key: Key('live-researchers-only'),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'The live monitor is for researchers of this study. Analysts '
            'can read the observations and the report.',
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        final selected = c.selectedId;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PilotCard(
              title: 'Sessions running now',
              caption: 'Sessions that have not ended and started within the '
                  'last 12 hours. Pick one to watch it live.',
              trailing: OutlinedButton.icon(
                key: const Key('live-refresh'),
                onPressed: c.activeLoading ? null : c.loadActive,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
              children: [
                if (c.activeError != null)
                  MessageBanner(key: const Key('live-active-error'), message: c.activeError!)
                else if (c.activeLoading && !c.activeLoaded)
                  const BusyBox()
                else if (c.active.isEmpty)
                  const EmptyNote(
                    'No session is running right now. Press Refresh when a '
                    'participant has started one.',
                  )
                else
                  Column(
                    key: const Key('active-list'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < c.active.length; i++) ...[
                        if (i > 0) const Divider(height: 12),
                        _ActiveRow(
                          session: c.active[i],
                          selected: c.active[i].sessionId == selected,
                          onMonitor: () => c.select(c.active[i].sessionId),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
            if (selected != null) ...[
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, constraints) {
                final panel = LivePanel(controller: c);
                final observations = SessionObservations(
                  key: ValueKey('live-observations-$selected'),
                  studyId: widget.studyId,
                  sessionId: selected,
                  canEdit: widget.canEdit,
                  sessionTimeMs: () => c.live?.lastSampleTMs,
                );
                if (constraints.maxWidth >= 1000) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: panel),
                      const SizedBox(width: 16),
                      SizedBox(width: 400, child: observations),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [panel, const SizedBox(height: 12), observations],
                );
              }),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Nothing is monitored. Nothing is logged until you press '
                  'Monitor on a session.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ActiveRow extends StatelessWidget {
  const _ActiveRow({
    required this.session,
    required this.selected,
    required this.onMonitor,
  });

  final ActiveSession session;
  final bool selected;
  final VoidCallback onMonitor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = session.lastEvent;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Container(
      key: Key('active-${session.sessionId}'),
      color: selected ? AppColors.tealTint : null,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 96, child: CodeText(session.participantCode)),
          SizedBox(
            width: 110,
            child: Text(sessionStatusLabel(session.status)),
          ),
          Text(session.devicePlatform ?? 'unknown device', style: muted),
          Text('Started ${formatTimestamp(session.createdAt)}', style: muted),
          Text(
            last == null
                ? 'No event yet'
                : 'Last event: ${last.type} at ${formatClockMs(last.tMs)}',
            style: muted,
          ),
          selected
              ? FilledButton(
                  key: Key('monitor-${session.sessionId}'),
                  onPressed: null,
                  child: const Text('Monitoring'),
                )
              : OutlinedButton(
                  key: Key('monitor-${session.sessionId}'),
                  onPressed: onMonitor,
                  child: const Text('Monitor'),
                ),
        ],
      ),
    );
  }
}
