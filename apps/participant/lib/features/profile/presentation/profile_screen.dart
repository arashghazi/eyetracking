import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../erase/presentation/erase_section.dart';
import '../application/profile_controller.dart';
import 'chip_list_editor.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileController _controller;
  final _name = TextEditingController();
  final _voice = TextEditingController();
  final _face = TextEditingController();
  bool _filled = false;

  @override
  void initState() {
    super.initState();
    _controller = ProfileController(AppScope.read(context).profile);
    _controller.addListener(_fillOnce);
    _controller.load();
  }

  /// Copies the loaded profile into the text fields the first time it arrives.
  void _fillOnce() {
    if (_filled || !_controller.loaded) return;
    _filled = true;
    final p = _controller.draft;
    _name.text = p.displayName;
    _voice.text = p.voicePreference;
    _face.text = p.facePreference;
  }

  @override
  void dispose() {
    _controller.dispose();
    _name.dispose();
    _voice.dispose();
    _face.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final c = _controller;
          if (!c.loaded) {
            return c.loading
                ? const Center(child: CircularProgressIndicator())
                : PageFrame(
                    banner: c.error != null
                        ? MessageBanner(
                            message: c.error!,
                            onDismiss: c.dismissError,
                          )
                        : null,
                    children: [
                      OutlinedButton(
                        onPressed: c.load,
                        child: const Text('Reload'),
                      ),
                    ],
                  );
          }
          final p = c.draft;
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
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Everything here is optional and can be changed at any time.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('display-name'),
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                          helperText: 'What we should call you on screen.',
                        ),
                        textInputAction: TextInputAction.next,
                        onChanged: c.setDisplayName,
                      ),
                      const SizedBox(height: 16),
                      Text('How would you like to respond?',
                          style: theme.textTheme.titleSmall),
                      RadioGroup<ResponseMode>(
                        groupValue: p.responseMode,
                        onChanged: (v) {
                          if (v != null) c.setResponseMode(v);
                        },
                        child: Column(
                          children: [
                            for (final mode in ResponseMode.values)
                              RadioListTile<ResponseMode>(
                                key: Key('response-${mode.wire}'),
                                value: mode,
                                title: Text(mode.label),
                                contentPadding: EdgeInsets.zero,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('voice-preference'),
                        controller: _voice,
                        decoration: const InputDecoration(
                          labelText: 'Voice preference',
                        ),
                        textInputAction: TextInputAction.next,
                        onChanged: c.setVoicePreference,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('face-preference'),
                        controller: _face,
                        decoration: const InputDecoration(
                          labelText: 'Face preference',
                        ),
                        textInputAction: TextInputAction.next,
                        onChanged: c.setFacePreference,
                      ),
                      const SizedBox(height: 16),
                      Text('Speed', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      SegmentedButton<Speed>(
                        key: const Key('speed'),
                        showSelectedIcon: false,
                        segments: [
                          for (final s in Speed.values)
                            ButtonSegment(value: s, label: Text(s.label)),
                        ],
                        selected: {p.speed},
                        onSelectionChanged: (s) => c.setSpeed(s.first),
                        style: SegmentedButton.styleFrom(
                          shape: const RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.all(Radius.circular(kRadius)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ChipListEditor(
                        label: 'Accessibility needs',
                        hint: 'For example: larger text',
                        values: p.accessibilityNeeds,
                        onAdd: c.addNeed,
                        onRemove: c.removeNeed,
                      ),
                      const SizedBox(height: 20),
                      ChipListEditor(
                        label: 'Interests',
                        hint: 'For example: trains',
                        values: p.interests,
                        onAdd: c.addInterest,
                        onRemove: c.removeInterest,
                      ),
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(
                          key: const Key('profile-save'),
                          onPressed: c.saving ? null : c.save,
                          child: Text(c.saving ? 'Saving...' : 'Save profile'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const EraseSection(),
            ],
          );
        },
      ),
    );
  }
}
