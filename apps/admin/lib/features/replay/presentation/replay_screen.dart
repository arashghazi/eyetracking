
import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../app_scope.dart';
import '../../sessions/presentation/session_widgets.dart';
import '../application/replay_controller.dart';
import 'replay_canvas.dart';
import 'replay_timeline.dart';

/// Replays one session: the participant's screen with the layout, the gaze
/// estimate and its trail, a scrubber and, when the session played clips,
/// the stimulus video in step with the timeline.
class ReplayScreen extends StatefulWidget {
  const ReplayScreen({
    super.key,
    required this.studyId,
    required this.sessionId,
    required this.participantCode,
  });

  final int studyId;
  final String sessionId;
  final String participantCode;

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen>
    with SingleTickerProviderStateMixin {
  late final ReplayController _controller;
  late final Ticker _ticker;
  final _focus = FocusNode(debugLabel: 'replay');
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _controller = ReplayController(
      AppScope.read(context).replay,
      widget.studyId,
      widget.sessionId,
    );
    _ticker = createTicker(_onTick);
    _controller.addListener(_syncTicker);
    _controller.load();
  }

  @override
  void dispose() {
    _controller.removeListener(_syncTicker);
    _ticker.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed - _lastTick;
    _lastTick = elapsed;
    _controller.advance(dt);
  }

  void _syncTicker() {
    if (_controller.playing && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (!_controller.playing && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Replay of ${widget.participantCode}')),
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _controller.step(-ReplayController.stepMs),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _controller.step(ReplayController.stepMs),
        },
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final c = _controller;
              final bundle = c.bundle;
              return PageFrame(
                maxWidth: 1200,
                // A handful of children: keep them all built, so the
                // stimulus video is not torn down when it scrolls away.
                buildAll: true,
                banner: c.error != null
                    ? MessageBanner(message: c.error!, onDismiss: c.dismissError)
                    : null,
                children: [
                  if (bundle == null)
                    c.loading
                        ? const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton(
                              key: const Key('retry-replay'),
                              onPressed: c.load,
                              child: const Text('Try again'),
                            ),
                          )
                  else
                    ..._content(context, c, bundle),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, ReplayController c, ReplayBundle b) {
    final theme = Theme.of(context);
    final protocol = b.session.protocol;
    final canvasCard = _CanvasCard(controller: c, bundle: b, onTap: _focus.requestFocus);
    final stimulus = b.hasMedia ? _StimulusPanel(controller: c) : null;
    return [
      Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            b.session.participantCode,
            style: theme.textTheme.titleLarge?.copyWith(
              fontFamily: 'monospace',
              fontFamilyFallback: kMonospaceFallback,
            ),
          ),
          QualityBadge(quality: b.session.quality, compact: false),
          SyntheticBadge(synthetic: b.session.synthetic),
          if (protocol != null)
            Text(
              '${protocol.name}${protocol.version > 0 ? ' · version ${protocol.version}' : ''}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          Text(
            'Screen ${b.screen.w.round()} × ${b.screen.h.round()} px',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const _Captions(),
      const SizedBox(height: 12),
      if (!b.hasSamples) ...[
        const MessageBanner(
          message: 'This session has no stored samples, so there is no gaze to replay.',
          kind: BannerKind.info,
        ),
        const SizedBox(height: 12),
      ],
      LayoutBuilder(builder: (context, constraints) {
        if (stimulus != null && constraints.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: canvasCard),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: stimulus),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            canvasCard,
            if (stimulus != null) ...[const SizedBox(height: 12), stimulus],
          ],
        );
      }),
      const SizedBox(height: 12),
      _Controls(controller: c),
      const SizedBox(height: 8),
      _TimelineCard(controller: c, bundle: b),
      const SizedBox(height: 12),
      _Facts(bundle: b),
    ];
  }
}

// -------------------------------------------------------------- captions

class _Captions extends StatelessWidget {
  const _Captions();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.videocam_off_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No participant video exists',
                    key: const Key('caption-no-video'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'The camera image is never stored. This replay draws the '
              "participant's screen, the stimulus layout and the gaze "
              'estimate only.',
              style: muted,
            ),
            const SizedBox(height: 4),
            Text(
              'Display only; no smoothing',
              key: const Key('caption-smoothing'),
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              'Each dot is one estimate as the model produced it. Showing it '
              'does not make it more accurate.',
              style: muted,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- canvas

class _CanvasCard extends StatelessWidget {
  const _CanvasCard({
    required this.controller,
    required this.bundle,
    required this.onTap,
  });

  final ReplayController controller;
  final ReplayBundle bundle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    final trial = c.activeTrial;
    final ratio = bundle.screen.w > 0 && bundle.screen.h > 0
        ? (bundle.screen.w / bundle.screen.h).clamp(0.6, 2.4)
        : 16 / 9;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text(
                  formatClockMs(c.positionMs),
                  key: const Key('replay-time'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  'Segment: ${c.activeSegment?.label ?? '-'}',
                  key: const Key('replay-segment'),
                ),
                Text(
                  'Gaze: ${c.regionText}',
                  key: const Key('replay-region'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (trial != null)
                  Text(
                    'Number shown: ${trial.numberShown} '
                    '(stage ${trial.stageIndex + 1}, trial ${trial.trialIndex + 1})',
                    key: const Key('replay-trial'),
                  ),
                if (c.activePause != null)
                  const Text('Paused', key: Key('replay-paused')),
                if (c.activeGap != null)
                  const Text('Gap: no samples', key: Key('replay-gap')),
              ],
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onTap,
              child: AspectRatio(
                aspectRatio: ratio.toDouble(),
                child: ClipRect(
                  child: CustomPaint(
                    key: const Key('replay-canvas'),
                    painter: ReplayCanvasPainter(
                      screen: bundle.screen,
                      positionMs: c.positionMs,
                      layout: c.activeLayout?.layout,
                      sample: c.currentSample,
                      trail: c.trail,
                      trial: trial,
                      trailMs: ReplayController.trailMs,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- controls

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});

  final ReplayController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          key: const Key('replay-play'),
          onPressed: c.toggle,
          icon: Icon(c.playing ? Icons.pause : Icons.play_arrow, size: 20),
          label: Text(c.playing ? 'Pause' : 'Play'),
        ),
        IconButton.outlined(
          key: const Key('replay-step-back'),
          tooltip: 'Back ${ReplayController.stepMs} ms (left arrow)',
          onPressed: () => c.step(-ReplayController.stepMs),
          icon: const Icon(Icons.skip_previous),
        ),
        IconButton.outlined(
          key: const Key('replay-step-forward'),
          tooltip: 'Forward ${ReplayController.stepMs} ms (right arrow)',
          onPressed: () => c.step(ReplayController.stepMs),
          icon: const Icon(Icons.skip_next),
        ),
        SegmentedButton<double>(
          key: const Key('replay-speed'),
          showSelectedIcon: false,
          segments: [
            for (final s in ReplayController.speeds)
              ButtonSegment(
                value: s,
                label: Text('${s == s.roundToDouble() ? s.toInt() : s}×'),
              ),
          ],
          selected: {c.speed},
          onSelectionChanged: (v) => c.setSpeed(v.first),
          style: SegmentedButton.styleFrom(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(kRadius)),
            ),
          ),
        ),
        Text(
          'Left and right arrow keys step ${ReplayController.stepMs} ms.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- timeline

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.controller, required this.bundle});

  final ReplayController controller;
  final ReplayBundle bundle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text('Timeline', style: theme.textTheme.titleSmall),
                Text(
                  '${formatClockMs(controller.positionMs)} / '
                  '${formatClockMs(bundle.durationMs)}',
                  key: const Key('replay-position'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ReplayTimeline(
              bundle: bundle,
              positionMs: controller.positionMs,
              onSeek: controller.seek,
            ),
            const SizedBox(height: 8),
            const ReplayTimelineLegend(),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- stimulus

class _StimulusPanel extends StatelessWidget {
  const _StimulusPanel({required this.controller});

  final ReplayController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    final media = c.stageMedia;
    final active = c.activeMedia;
    final deps = AppScope.read(context);
    return Card(
      key: const Key('replay-stimulus'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Stimulus video', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              media == null
                  ? ''
                  : (active == null
                      ? 'No clip plays at this time. Last clip: ${media.mediaKey}.'
                      : 'Clip ${media.mediaKey} of segment ${media.segmentId}, '
                          '${(c.mediaSeconds ?? 0).toStringAsFixed(1)} s in.'),
              key: const Key('replay-media-note'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            if (media != null && media.hasUrl)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Opacity(
                  opacity: active == null ? 0.45 : 1,
                  child: deps.videoStage(
                    context,
                    VideoStageConfig(
                      url: media.url,
                      controller: c.video,
                      autoplay: false,
                      onError: (_) {},
                    ),
                  ),
                ),
              )
            else if (media != null)
              const Text(
                'The link to this clip is not available: the server could '
                'not tell which file it was.',
                key: Key('replay-media-missing'),
              ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- facts

class _Facts extends StatelessWidget {
  const _Facts({required this.bundle});

  final ReplayBundle bundle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final quality = bundle.session.quality;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('About this replay', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '${bundle.samples.length} samples · ${bundle.gaps.length} gaps · '
              '${bundle.pauses.length} pauses · ${bundle.trials.length} trials · '
              '${bundle.events.length} events',
              key: const Key('replay-facts'),
              style: muted,
            ),
            if (quality != null && quality.reasons.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Quality: ${quality.reasonsText.replaceAll('\n', '; ')}', style: muted),
            ],
          ],
        ),
      ),
    );
  }
}
