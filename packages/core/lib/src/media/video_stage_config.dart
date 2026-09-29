import 'package:flutter/widgets.dart';

import '../models/content.dart';
import '../models/layout.dart';

/// What a video stage needs to know: which video to play and whom to tell
/// what happened. Shared by the browser widget and the test double so the
/// app can swap one for the other.
class VideoStageConfig {
  const VideoStageConfig({
    required this.url,
    this.onEnded,
    this.onError,
    this.onRect,
    this.onPlaying,
  });

  /// Signed media URL, used exactly as the server gave it.
  final String url;

  /// The video played to its end.
  final VoidCallback? onEnded;

  /// The video could not be loaded or played; the argument is safe to show.
  final ValueChanged<String>? onError;

  /// The rectangle (CSS pixels of the screen) where the video is actually
  /// drawn, letterboxing excluded. Called again when the window is resized.
  final ValueChanged<Box>? onRect;

  /// Playback started.
  final VoidCallback? onPlaying;
}

/// Builds the widget that plays one video segment.
typedef VideoStageBuilder = Widget Function(
  BuildContext context,
  VideoStageConfig config,
);

/// Reports where a video of [intrinsic] size is drawn inside [child]'s box
/// with `object-fit: contain`, in screen coordinates. Reports again whenever
/// the box moves or is resized.
class VideoRectReporter extends StatefulWidget {
  const VideoRectReporter({
    super.key,
    required this.intrinsic,
    required this.onRect,
    required this.child,
  });

  /// Pixel size of the video, or null until its metadata is known.
  final Size? intrinsic;
  final ValueChanged<Box>? onRect;
  final Widget child;

  @override
  State<VideoRectReporter> createState() => _VideoRectReporterState();
}

class _VideoRectReporterState extends State<VideoRectReporter> {
  Box? _last;

  void _report() {
    if (!mounted) return;
    final size = widget.intrinsic;
    final render = context.findRenderObject();
    if (size == null || render is! RenderBox || !render.hasSize) return;
    final origin = render.localToGlobal(Offset.zero);
    final rect = containedVideoRect(
      Box(origin.dx, origin.dy, render.size.width, render.size.height),
      size.width,
      size.height,
    );
    final last = _last;
    if (last != null &&
        (last.x - rect.x).abs() < 0.5 &&
        (last.y - rect.y).abs() < 0.5 &&
        (last.w - rect.w).abs() < 0.5 &&
        (last.h - rect.h).abs() < 0.5) {
      return;
    }
    _last = rect;
    widget.onRect?.call(rect);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    return widget.child;
  }
}
