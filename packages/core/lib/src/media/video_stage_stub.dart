import 'package:flutter/material.dart';

import 'video_stage_config.dart';

/// Outside the browser there is no player yet: report that the video cannot
/// be shown, so the app offers its "video is not ready" state.
class VideoStage extends StatefulWidget {
  const VideoStage({super.key, required this.config});

  final VideoStageConfig config;

  @override
  State<VideoStage> createState() => _VideoStageState();
}

class _VideoStageState extends State<VideoStage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.config.onError?.call('Video playback is available in the web app.');
      }
    });
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            'Video playback is available in the web app.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
}
