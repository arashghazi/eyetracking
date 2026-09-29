import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../application/information_sheet_controller.dart';

class InformationSheetTab extends StatefulWidget {
  const InformationSheetTab({super.key, required this.studyId});

  final int studyId;

  @override
  State<InformationSheetTab> createState() => _InformationSheetTabState();
}

class _InformationSheetTabState extends State<InformationSheetTab>
    with AutomaticKeepAliveClientMixin {
  late final InformationSheetController _controller;
  final _aims = TextEditingController();
  final _discomfort = TextEditingController();
  final _benefits = TextEditingController();
  final _dataHandling = TextEditingController();
  final _stopRules = TextEditingController();
  bool _filled = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = InformationSheetController(
      AppScope.read(context).informationSheet,
      widget.studyId,
    );
    _controller.addListener(_fillOnce);
    _controller.load();
  }

  /// Copies the published sheet into the fields the first time it arrives.
  void _fillOnce() {
    if (_filled || !_controller.loaded) return;
    _filled = true;
    final d = _controller.draft;
    _aims.text = d.aims;
    _discomfort.text = d.discomfortSources;
    _benefits.text = d.benefits;
    _dataHandling.text = d.dataHandling;
    _stopRules.text = d.stopRules;
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final t in [_aims, _discomfort, _benefits, _dataHandling, _stopRules]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _confirmAndPublish() async {
    final current = _controller.current;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish a new version?'),
        content: Text(
          current == null
              ? 'This publishes the first version of the information sheet.'
              : 'This publishes version ${current.version + 1}. Participants '
                  'who agreed to an earlier version will be asked to read the '
                  'sheet and consent again before they count as ready.',
        ),
        actions: [
          TextButton(
            key: const Key('publish-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('publish-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _controller.publish();
  }

  Widget _field(
    Key key,
    TextEditingController controller,
    String label,
    void Function(String) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        key: key,
        controller: controller,
        decoration: InputDecoration(
          labelText: '$label *',
          alignLabelWithHint: true,
        ),
        minLines: 3,
        maxLines: 12,
        keyboardType: TextInputType.multiline,
        onChanged: onChanged,
      ),
    );
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
            Text('Information sheet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            if (c.loading && !c.loaded)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!c.loaded)
              OutlinedButton(onPressed: c.load, child: const Text('Try again'))
            else ...[
              Text(
                c.current == null
                    ? 'No information sheet has been published for this study yet.'
                    : 'Current version: ${c.current!.version}, published '
                        '${formatTimestamp(c.current!.publishedAt)}.',
                key: const Key('sheet-version'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'All five sections are required. Each publish creates a new version.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _field(const Key('sheet-aims'), _aims, 'Aims of the study',
                          (v) => c.edit(aims: v)),
                      _field(
                        const Key('sheet-discomfort'),
                        _discomfort,
                        'Possible sources of discomfort',
                        (v) => c.edit(discomfortSources: v),
                      ),
                      _field(const Key('sheet-benefits'), _benefits,
                          'Possible benefits', (v) => c.edit(benefits: v)),
                      _field(
                        const Key('sheet-data'),
                        _dataHandling,
                        'How data is handled',
                        (v) => c.edit(dataHandling: v),
                      ),
                      _field(
                        const Key('sheet-stop'),
                        _stopRules,
                        'Stopping and starting again',
                        (v) => c.edit(stopRules: v),
                      ),
                      FilledButton(
                        key: const Key('publish-sheet'),
                        onPressed: c.canPublish ? _confirmAndPublish : null,
                        child: Text(
                          c.publishing ? 'Publishing...' : 'Publish new version',
                        ),
                      ),
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
