import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_dependencies.dart';
import '../../../app_scope.dart';
import '../../exports/application/download_controller.dart';
import '../application/debrief_form_controller.dart';
import '../application/pilot_report_controller.dart';
import '../application/threshold_review_controller.dart';
import '../application/tracker_comparison_controller.dart';
import 'debrief_section.dart';
import 'live_section.dart';
import 'report_section.dart';
import 'thresholds_section.dart';
import 'tracker_section.dart';

/// The five parts of the Pilot tab.
enum PilotSection {
  live('Live'),
  thresholds('Thresholds'),
  tracker('Tracker comparison'),
  report('Report'),
  debrief('Questions after a session');

  const PilotSection(this.label);

  final String label;
}

/// The supervised pilot: watch sessions live and write observations, review
/// thresholds before saving a new settings version, compare the webcam with a
/// research eye tracker, read the pilot report and edit the questions asked
/// after a session.
///
/// Researchers write; analysts read what the server lets them read.
class PilotTab extends StatefulWidget {
  const PilotTab({
    super.key,
    required this.studyId,
    required this.canEdit,
    this.tabIndex,
  });

  final int studyId;

  /// Researchers (and administrators) monitor, import and save; analysts
  /// only read.
  final bool canEdit;

  /// Position of this tab in the study screen; the live monitor stops
  /// polling while another tab is shown.
  final int? tabIndex;

  @override
  State<PilotTab> createState() => _PilotTabState();
}

class _PilotTabState extends State<PilotTab> with AutomaticKeepAliveClientMixin {
  PilotSection _section = PilotSection.live;
  late final AppDependencies _deps;
  TabController? _tabs;
  bool _visible = true;

  ThresholdReviewController? _thresholds;
  TrackerComparisonController? _tracker;
  PilotReportController? _report;
  DebriefFormController? _debrief;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _deps = AppScope.read(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabs = DefaultTabController.maybeOf(context);
    if (tabs != _tabs) {
      _tabs?.removeListener(_onTab);
      _tabs = tabs;
      _visible = tabs == null || widget.tabIndex == null || tabs.index == widget.tabIndex;
      tabs?.addListener(_onTab);
    }
  }

  void _onTab() {
    final tabs = _tabs;
    if (tabs == null || tabs.indexIsChanging || widget.tabIndex == null) return;
    final visible = tabs.index == widget.tabIndex;
    if (visible != _visible) setState(() => _visible = visible);
  }

  @override
  void dispose() {
    _tabs?.removeListener(_onTab);
    _thresholds?.dispose();
    _tracker?.dispose();
    _report?.dispose();
    _debrief?.dispose();
    super.dispose();
  }

  ThresholdReviewController get _thresholdsController =>
      _thresholds ??= ThresholdReviewController(
        _deps.pilot,
        _deps.measurementSettings,
        widget.studyId,
        canEdit: widget.canEdit,
      )..load();

  TrackerComparisonController get _trackerController =>
      _tracker ??= TrackerComparisonController(
        _deps.pilot,
        _deps.sessions,
        _deps.mediaPicker,
        widget.studyId,
        canImport: widget.canEdit,
      )..loadSessions();

  PilotReportController get _reportController =>
      _report ??= PilotReportController(
        _deps.pilot,
        widget.studyId,
        DownloadController(_deps.saveFile),
      )..load();

  DebriefFormController get _debriefController =>
      _debrief ??= DebriefFormController(
        _deps.pilot,
        widget.studyId,
        canEdit: widget.canEdit,
      )..load();

  Widget _sectionBody() => switch (_section) {
        PilotSection.live => LiveSection(
            key: const Key('section-live'),
            studyId: widget.studyId,
            canEdit: widget.canEdit,
            visible: _visible,
          ),
        PilotSection.thresholds => ThresholdsSection(
            key: const Key('section-thresholds'),
            controller: _thresholdsController,
          ),
        PilotSection.tracker => TrackerSection(
            key: const Key('section-tracker'),
            controller: _trackerController,
          ),
        PilotSection.report => ReportSection(
            key: const Key('section-report'),
            controller: _reportController,
          ),
        PilotSection.debrief => DebriefSection(
            key: const Key('section-debrief'),
            controller: _debriefController,
          ),
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return PageFrame(
      maxWidth: 1200,
      buildAll: true,
      children: [
        Text('Supervised pilot', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Watch a session as it runs, tune the thresholds on what was '
          'recorded, compare with a research eye tracker and read the pilot '
          'report. Everything here is under research codes.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        // A wrapping row of choices: on a phone every part stays in view.
        Wrap(
          key: const Key('pilot-sections'),
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in PilotSection.values)
              ChoiceChip(
                key: Key('pilot-section-${s.name}'),
                label: Text(s.label),
                selected: _section == s,
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                onSelected: (_) => setState(() => _section = s),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionBody(),
      ],
    );
  }
}
