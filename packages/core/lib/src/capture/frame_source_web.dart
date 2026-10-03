// Web-only camera capture. Loaded through a conditional import, so it is
// never compiled for the VM or Android.
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../models/session.dart';
import 'frame_source.dart';

/// Camera capture in the browser: `getUserMedia` video, drawn on a hidden
/// canvas and encoded as JPEG (quality 0.7). Frames never leave memory
/// except to the gaze estimator. The chosen camera's device id is kept in
/// localStorage so the next session opens the same camera.
class WebFrameSource extends FrameSource {
  static const _viewType = 'eyetracking-camera-preview';
  static const _storageKey = 'eyetracking.camera_device_id';
  static bool _registered = false;
  static final List<web.HTMLVideoElement> _previews = [];
  static WebFrameSource? _current;

  web.MediaStream? _stream;
  web.HTMLVideoElement? _video;
  web.HTMLCanvasElement? _canvas;
  List<CameraDevice> _cameras = const [];
  String? _activeId;
  String? _activeLabel;
  String? _chosenId;
  bool _chosenLoaded = false;
  int _width = 0;
  int _height = 0;
  int _askW = 640;
  int _askH = 480;

  final _events = StreamController<FrameSourceEvent>.broadcast();
  Timer? _debounce;
  double _dpr = 1;
  int _innerW = 0;
  int _innerH = 0;

  late final JSFunction _onDeviceChange = _handleDeviceChange.toJS;
  late final JSFunction _onViewport = _handleViewport.toJS;
  late final JSFunction _onTrackEnded = _handleTrackEnded.toJS;
  web.ScreenOrientation? _orientation;

  @override
  bool get isActive => _stream != null;

  @override
  List<CameraDevice> get cameras => _cameras;

  @override
  String? get activeCameraId => _activeId;

  @override
  String? get activeCameraLabel => _activeLabel;

  @override
  int get frameWidth => _width;

  @override
  int get frameHeight => _height;

  @override
  Stream<FrameSourceEvent> get events => _events.stream;

  @override
  Future<void> start({int width = 640, int height = 480}) async {
    if (_stream != null) return;
    _askW = width;
    _askH = height;
    await _open(_chosen, fallback: true);
  }

  @override
  Future<void> selectCamera(String deviceId) async {
    final previous = _chosen;
    _chosenId = deviceId;
    if (_stream == null || deviceId == _activeId) {
      _remember(deviceId);
      return;
    }
    await stop();
    try {
      await _open(deviceId, fallback: false);
      _remember(deviceId);
    } on FrameSourceException {
      _chosenId = previous;
      try {
        await _open(previous, fallback: true);
      } catch (_) {
        // The participant sees the first error; the preview stays dark.
      }
      rethrow;
    }
  }

  /// The camera chosen on this device, loaded once from localStorage.
  String? get _chosen {
    if (!_chosenLoaded) {
      _chosenLoaded = true;
      try {
        final stored = web.window.localStorage.getItem(_storageKey);
        if (stored != null && stored.isNotEmpty) _chosenId ??= stored;
      } catch (_) {
        // Storage can be disabled; the browser default is used then.
      }
    }
    return _chosenId;
  }

  void _remember(String deviceId) {
    try {
      web.window.localStorage.setItem(_storageKey, deviceId);
    } catch (_) {
      // Not remembered across sessions; this session still uses it.
    }
  }

  Future<web.MediaStream> _request(String? deviceId) => web
      .window.navigator.mediaDevices
      .getUserMedia(web.MediaStreamConstraints(
        video: {
          'width': {'ideal': _askW},
          'height': {'ideal': _askH},
          if (deviceId != null)
            'deviceId': {'exact': deviceId}
          else
            'facingMode': 'user',
        }.jsify()!,
        audio: false.toJS,
      ))
      .toDart;

  /// Opens [deviceId] (the browser default when null). With [fallback], a
  /// remembered camera that is no longer connected gives way to the default.
  Future<void> _open(String? deviceId, {required bool fallback}) async {
    _registerPreviewFactory();
    web.MediaStream stream;
    try {
      stream = await _request(deviceId);
    } catch (e) {
      final gone = e.toString().contains('Overconstrained') ||
          e.toString().contains('NotFound');
      if (!fallback || deviceId == null || !gone) {
        throw FrameSourceException(_cameraErrorMessage(e));
      }
      try {
        stream = await _request(null);
      } catch (e) {
        throw FrameSourceException(_cameraErrorMessage(e));
      }
    }

    final video = web.document.createElement('video') as web.HTMLVideoElement
      ..muted = true
      ..autoplay = true
      ..playsInline = true
      ..srcObject = stream;
    // Kept in the page (invisible) so browsers keep decoding frames.
    video.style.cssText =
        'position:fixed;left:0;top:0;width:2px;height:2px;opacity:0;pointer-events:none;';
    web.document.body!.append(video);
    try {
      await video.play().toDart;
    } catch (_) {
      // Autoplay is allowed for muted video; ignore rejections from a pause.
    }

    _stream = stream;
    _video = video;
    _canvas = web.document.createElement('canvas') as web.HTMLCanvasElement;
    _current = this;
    final tracks = stream.getVideoTracks().toDart;
    _activeLabel = tracks.isEmpty ? null : tracks.first.label;
    _activeId = null;
    if (tracks.isNotEmpty) {
      tracks.first.addEventListener('ended', _onTrackEnded);
      try {
        final id = tracks.first.getSettings().deviceId;
        if (id.isNotEmpty) _activeId = id;
      } catch (_) {
        // Older browsers: the id is matched by label below.
      }
    }
    _width = video.videoWidth;
    _height = video.videoHeight;
    await _refreshCameras();
    _activeId ??= _cameras
        .where((c) => c.label == _activeLabel)
        .map((c) => c.id)
        .firstOrNull;
    _attachListeners();
    for (final p in _previews) {
      p.srcObject = stream;
    }
  }

  @override
  Stream<CapturedFrame> frames({double fps = 10}) {
    late final StreamController<CapturedFrame> controller;
    Timer? timer;
    var busy = false;
    controller = StreamController<CapturedFrame>(
      onListen: () {
        final interval = Duration(milliseconds: (1000 / fps).round());
        timer = Timer.periodic(interval, (_) async {
          if (busy || _stream == null || controller.isClosed) return;
          busy = true;
          try {
            final frame = await _grab();
            if (frame != null && !controller.isClosed) controller.add(frame);
          } catch (_) {
            // A dropped frame is fine; the next tick tries again.
          } finally {
            busy = false;
          }
        });
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
    );
    return controller.stream;
  }

  Future<CapturedFrame?> _grab() async {
    final video = _video;
    final canvas = _canvas;
    if (video == null || canvas == null) return null;
    final w = video.videoWidth;
    final h = video.videoHeight;
    if (w == 0 || h == 0) return null;
    if (canvas.width != w) canvas.width = w;
    if (canvas.height != h) canvas.height = h;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    ctx.drawImage(video, 0, 0);
    final tMs = nowMs;
    _width = w;
    _height = h;

    final completer = Completer<web.Blob?>();
    canvas.toBlob(
      ((web.Blob? blob) => completer.complete(blob)).toJS,
      'image/jpeg',
      0.7.toJS,
    );
    final blob = await completer.future;
    if (blob == null) return null;
    final buffer = await blob.arrayBuffer().toDart;
    return CapturedFrame(
      jpeg: buffer.toDart.asUint8List(),
      width: w,
      height: h,
      tMs: tMs,
    );
  }

  @override
  Future<void> stop() async {
    _detachListeners();
    _debounce?.cancel();
    final stream = _stream;
    _stream = null;
    if (stream != null) {
      for (final track in stream.getTracks().toDart) {
        track.removeEventListener('ended', _onTrackEnded);
        track.stop();
      }
    }
    for (final p in _previews) {
      p.srcObject = null;
    }
    _video?.srcObject = null;
    _video?.remove();
    _video = null;
    _canvas = null;
    if (identical(_current, this)) _current = null;
  }

  @override
  Widget preview() {
    _registerPreviewFactory();
    return const HtmlElementView(viewType: _viewType);
  }

  // ------------------------------------------------------------ previews

  static void _registerPreviewFactory() {
    if (_registered) return;
    _registered = true;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final video = web.document.createElement('video') as web.HTMLVideoElement
        ..muted = true
        ..autoplay = true
        ..playsInline = true;
      video.style.cssText = 'width:100%;height:100%;object-fit:cover;'
          'transform:scaleX(-1);background:#000;border:0;';
      final stream = _current?._stream;
      if (stream != null) video.srcObject = stream;
      _previews.add(video);
      video.play().toDart.catchError((_) => null);
      return video;
    });
  }

  // -------------------------------------------------------------- events

  void _attachListeners() {
    web.window.navigator.mediaDevices
        .addEventListener('devicechange', _onDeviceChange);
    web.window.addEventListener('resize', _onViewport);
    web.window.addEventListener('orientationchange', _onViewport);
    _orientation = web.window.screen.orientation;
    _orientation?.addEventListener('change', _onViewport);
    _dpr = web.window.devicePixelRatio;
    _innerW = web.window.innerWidth;
    _innerH = web.window.innerHeight;
  }

  void _detachListeners() {
    web.window.navigator.mediaDevices
        .removeEventListener('devicechange', _onDeviceChange);
    web.window.removeEventListener('resize', _onViewport);
    web.window.removeEventListener('orientationchange', _onViewport);
    _orientation?.removeEventListener('change', _onViewport);
    _orientation = null;
  }

  Future<void> _refreshCameras() async {
    try {
      final devices =
          await web.window.navigator.mediaDevices.enumerateDevices().toDart;
      final found = <CameraDevice>[];
      for (final d in devices.toDart) {
        if (d.kind != 'videoinput') continue;
        found.add(CameraDevice(
          id: d.deviceId,
          label: d.label.isEmpty ? 'Camera ${found.length + 1}' : d.label,
        ));
      }
      _cameras = found;
    } catch (_) {
      // Without the list the participant keeps the camera that opened.
    }
  }

  void _handleDeviceChange(web.Event _) {
    final before = List<CameraDevice>.of(_cameras);
    _refreshCameras().then((_) {
      if (_stream != null && !listEquals(before, _cameras)) {
        _events.add(FrameSourceEvent.cameraChanged);
      }
    });
  }

  void _handleTrackEnded(web.Event _) {
    if (_stream != null) _events.add(FrameSourceEvent.cameraChanged);
  }

  void _handleViewport(web.Event _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (_stream == null) return;
      final dpr = web.window.devicePixelRatio;
      final w = web.window.innerWidth;
      final h = web.window.innerHeight;
      if ((dpr - _dpr).abs() > 0.001) {
        _dpr = dpr;
        _innerW = w;
        _innerH = h;
        _events.add(FrameSourceEvent.zoomChanged);
      } else if (w != _innerW || h != _innerH) {
        _innerW = w;
        _innerH = h;
        _events.add(FrameSourceEvent.orientationChanged);
      }
    });
  }

  String _cameraErrorMessage(Object e) {
    final text = e.toString();
    if (text.contains('NotAllowed') || text.contains('Permission')) {
      return 'Camera access was not allowed. Allow the camera for this page in '
          'the browser address bar, then try again.';
    }
    if (text.contains('Overconstrained')) {
      return 'The chosen camera is not available. Check that it is connected '
          'or choose another camera.';
    }
    if (text.contains('NotFound') || text.contains('Devices not found')) {
      return 'No camera was found. Connect a camera and try again.';
    }
    if (text.contains('NotReadable') || text.contains('TrackStart')) {
      return 'The camera is being used by another program. Close it and try again.';
    }
    if (text.contains('SecurityError')) {
      return 'The browser blocked the camera on this address. Use https or localhost.';
    }
    return 'The camera could not be started. Check it and try again.';
  }
}

/// Facts about this browser for the session record.
DeviceInfo currentDeviceInfo() => DeviceInfo(
      platform: 'web',
      userAgent: web.window.navigator.userAgent,
    );

FrameSource createFrameSource() => WebFrameSource();
