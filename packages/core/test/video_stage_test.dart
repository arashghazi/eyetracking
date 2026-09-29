import 'package:eyetracking_core/eyetracking_core.dart';
import 'package:eyetracking_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child, {double w = 800, double h = 600}) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: w, height: h, child: child),
          ),
        ),
      );

  testWidgets('the fake plays for its duration, then reports the end',
      (tester) async {
    var playing = 0;
    var ended = 0;
    await tester.pumpWidget(host(FakeVideoStage(
      config: VideoStageConfig(
        url: '/media/a',
        onPlaying: () => playing++,
        onEnded: () => ended++,
      ),
      duration: const Duration(milliseconds: 500),
    )));
    await tester.pump();
    expect(playing, 1);
    expect(ended, 0);
    await tester.pump(const Duration(milliseconds: 400));
    expect(ended, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(ended, 1);
    expect(find.text('/media/a'), findsOneWidget);
  });

  testWidgets('a new url restarts the clock', (tester) async {
    var ended = 0;
    Widget stage(String url) => host(FakeVideoStage(
          config: VideoStageConfig(url: url, onEnded: () => ended++),
          duration: const Duration(milliseconds: 300),
        ));
    await tester.pumpWidget(stage('/a'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(stage('/b'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(ended, 0, reason: 'the first video was replaced before it ended');
    await tester.pump(const Duration(milliseconds: 200));
    expect(ended, 1);
  });

  testWidgets('a failing url reports an error instead of playing', (tester) async {
    final errors = <String>[];
    var ended = 0;
    await tester.pumpWidget(host(FakeVideoStage(
      config: VideoStageConfig(
        url: '/bad',
        onError: errors.add,
        onEnded: () => ended++,
      ),
      failUrls: {'/bad'},
    )));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(errors, ['The video could not be loaded.']);
    expect(ended, 0);
  });

  testWidgets('failOnce fails the first try only', (tester) async {
    final urls = {'/flaky'};
    final errors = <String>[];
    var ended = 0;
    Widget stage(int n) => host(KeyedSubtree(
          key: ValueKey(n),
          child: FakeVideoStage(
            config: VideoStageConfig(
              url: '/flaky',
              onError: errors.add,
              onEnded: () => ended++,
            ),
            failUrls: urls,
            failOnce: true,
            duration: const Duration(milliseconds: 50),
          ),
        ));
    await tester.pumpWidget(stage(1));
    await tester.pump();
    expect(errors, hasLength(1));
    await tester.pumpWidget(stage(2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(errors, hasLength(1));
    expect(ended, 1);
  });

  testWidgets('the rectangle of a 16:9 video in a wide box is letterboxed',
      (tester) async {
    final rects = <Box>[];
    await tester.pumpWidget(host(
      FakeVideoStage(
        config: VideoStageConfig(url: '/a', onRect: rects.add),
        duration: const Duration(seconds: 5),
      ),
      w: 800,
      h: 600,
    ));
    await tester.pump();
    await tester.pump();
    expect(rects, isNotEmpty);
    final rect = rects.last;
    // The box starts at the top-left of the window; 1920x1080 in 800x600.
    expect(rect.x, closeTo(0, 0.5));
    expect(rect.w, closeTo(800, 0.5));
    expect(rect.h, closeTo(450, 0.5));
    expect(rect.y, closeTo(75, 0.5));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the rectangle follows a resize', (tester) async {
    final rects = <Box>[];
    Widget stage(double w, double h) => host(
          FakeVideoStage(
            config: VideoStageConfig(url: '/a', onRect: rects.add),
            duration: const Duration(seconds: 5),
            intrinsic: const Size(1000, 1000),
          ),
          w: w,
          h: h,
        );
    await tester.pumpWidget(stage(800, 600));
    await tester.pump();
    await tester.pump();
    expect(rects.last.w, closeTo(600, 0.5), reason: 'square video in a 800x600 box');
    expect(rects.last.x, closeTo(100, 0.5));

    await tester.pumpWidget(stage(400, 600));
    await tester.pump();
    await tester.pump();
    expect(rects.last.w, closeTo(400, 0.5));
    expect(rects.last.y, closeTo(100, 0.5));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the rectangle is in window coordinates, not box coordinates',
      (tester) async {
    final rects = <Box>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.only(left: 30, top: 40),
          child: SizedBox(
            width: 400,
            height: 225,
            child: FakeVideoStage(
              config: VideoStageConfig(url: '/a', onRect: rects.add),
              duration: const Duration(seconds: 5),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(rects.last.x, closeTo(30, 0.5));
    expect(rects.last.y, closeTo(40, 0.5));
    expect(rects.last.w, closeTo(400, 0.5));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the builder makes a fake with the given plan', (tester) async {
    final builder = FakeVideoStage.builder(duration: const Duration(milliseconds: 20));
    var ended = 0;
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        ctx = context;
        return builder(context, VideoStageConfig(url: '/x', onEnded: () => ended++));
      }),
    ));
    expect(ctx, isNotNull);
    await tester.pump(const Duration(milliseconds: 40));
    expect(ended, 1);
  });
}
