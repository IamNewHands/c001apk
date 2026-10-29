import 'dart:io';

import 'package:c001apk_flutter/components/adaptive_main_scaffold.dart';
import 'package:c001apk_flutter/components/liquid_navigation_bar.dart';
import 'package:c001apk_flutter/components/liquid_top_bar.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('scroll-chrome-');
    Hive.init(directory.path);
    GStorage.settings = await Hive.openBox('settings');
  });
  setUp(() => GStorage.settings.clear());
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Widget feed() => ListView.builder(
        itemCount: 30,
        itemBuilder: (_, i) => SizedBox(height: 100, child: Text('项目 $i')),
      );

  Widget topBarPage() => LiquidTopBarScaffold(
        title: const Text('标题'),
        body: feed(),
      );

  Future<void> mount(
    WidgetTester tester, {
    double width = 400,
    Widget? body,
    int selectedIndex = 0,
    bool autoHideChrome = true,
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: platform),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          padding: const EdgeInsets.only(bottom: 24),
          viewPadding: const EdgeInsets.only(bottom: 24),
        ),
        child: AdaptiveMainScaffold(
          selectedIndex: selectedIndex,
          autoHideChrome: autoHideChrome,
          onDestinationSelected: (_) {},
          bodyBuilder: (_, __) => body ?? feed(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Reads the surface's current paint offset without exposing the controller.
  Rect rectOf(WidgetTester tester, Finder finder) => tester.getRect(finder);

  testWidgets('the bottom bar leaves while reading down and returns on the way up',
      (tester) async {
    await mount(tester);
    final bar = find.byType(LiquidNavigationBar);
    final shown = rectOf(tester, bar);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final hidden = rectOf(tester, bar);
    // Fully hidden means translated by exactly its own height.
    expect(hidden.top - shown.top, closeTo(shown.height, 0.5));

    // A flip locks the opposite direction for 400ms; a reader takes at least
    // that long before scrolling back up.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(rectOf(tester, bar).top, closeTo(shown.top, 0.5));
  });

  testWidgets('the chrome stays away while the scroll rests', (tester) async {
    await mount(tester);
    final bar = find.byType(LiquidNavigationBar);
    final shown = rectOf(tester, bar);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(rectOf(tester, bar).top, greaterThan(shown.top + 1));

    // Stopping to read must not throw the bars back in the reader's face.
    await tester.pump(const Duration(seconds: 2));
    expect(rectOf(tester, bar).top, greaterThan(shown.top + 1));

    // Only an upward scroll brings them back.
    // A flip locks the opposite direction for 400ms; a reader takes at least
    // that long before scrolling back up.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(rectOf(tester, bar).top, closeTo(shown.top, 0.5));
  });

  testWidgets('a tap on the content brings the chrome back', (tester) async {
    await mount(tester);
    final bar = find.byType(LiquidNavigationBar);
    final shown = rectOf(tester, bar);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(rectOf(tester, bar).top, greaterThan(shown.top + 1));

    // Tapping still reaches the content, so cards stay openable.
    await tester.tapAt(const Offset(200, 400));
    await tester.pumpAndSettle();
    expect(rectOf(tester, bar).top, closeTo(shown.top, 0.5));
  });

  testWidgets('the rail stays put while the toolbar still hides', (tester) async {
    await mount(tester, width: 900, body: topBarPage());
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(LiquidNavigationBar), findsNothing);
    final rail = rectOf(tester, find.byType(NavigationRail));
    final appBar = rectOf(tester, find.byType(AppBar));

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(rectOf(tester, find.byType(NavigationRail)), rail);
    expect(appBar.top - rectOf(tester, find.byType(AppBar)).top,
        closeTo(appBar.height, 0.5));
    await tester.pumpAndSettle();
  });

  testWidgets('turning auto-hide off keeps both surfaces in place',
      (tester) async {
    await tester.runAsync(
        () => GStorage.settings.put('scrollChromeAutoHide', false));
    await mount(tester);
    final bar = rectOf(tester, find.byType(LiquidNavigationBar));

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(rectOf(tester, find.byType(LiquidNavigationBar)), bar);
    await tester.pumpAndSettle();
  });

  testWidgets('a pull at the very top leaves the chrome alone', (tester) async {
    // iOS bounces, which is the only platform that reports scroll updates while
    // the offset is still pinned at the top.
    await mount(tester, platform: TargetPlatform.iOS);
    final bar = find.byType(LiquidNavigationBar);
    final shown = rectOf(tester, bar);

    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(rectOf(tester, bar).top, closeTo(shown.top, 0.5));

    // Real reading still hides it.
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(rectOf(tester, bar).top, greaterThan(shown.top + 1));
    await tester.pumpAndSettle();
  });

  testWidgets('a destination without a feed keeps the chrome fixed',
      (tester) async {
    await mount(tester, selectedIndex: 2, autoHideChrome: false);
    final bar = rectOf(tester, find.byType(LiquidNavigationBar));

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(rectOf(tester, find.byType(LiquidNavigationBar)), bar);
    await tester.pumpAndSettle();
  });

  /// Hides the bar and waits out the direction lock, which is what a reader
  /// does before scrolling the other way.
  Future<void> hideBar(WidgetTester tester, Finder bar, Rect shown) async {
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(rectOf(tester, bar).top, greaterThan(shown.top + 1));
  }

  testWidgets('a short nudge up leaves the chrome hidden', (tester) async {
    await mount(tester);
    final bar = find.byType(LiquidNavigationBar);
    final shown = rectOf(tester, bar);
    await hideBar(tester, bar, shown);

    // Well under the show threshold: the reader is still on the same post.
    await tester.drag(find.byType(ListView), const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(rectOf(tester, bar).top, greaterThan(shown.top + 1));
  });

  testWidgets('a decisive scroll-up waits out the dwell', (tester) async {
    await mount(tester);
    final bar = find.byType(LiquidNavigationBar);
    final shown = rectOf(tester, bar);
    await hideBar(tester, bar, shown);

    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pump(const Duration(milliseconds: 100));
    // Past the threshold, but the upward motion has not lasted long enough.
    expect(rectOf(tester, bar).top, greaterThan(shown.top + 1));

    await tester.pumpAndSettle();
    expect(rectOf(tester, bar).top, closeTo(shown.top, 0.5));
  });

  testWidgets('a moving bar paints no backdrop blur', (tester) async {
    await mount(tester);
    // Docked, the bar samples the feed behind it.
    expect(find.byType(BackdropFilter), findsWidgets);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    // Off screen and flat: no sample and no paint while the reader reads.
    expect(find.byType(BackdropFilter), findsNothing);

    await tester.tapAt(const Offset(200, 400));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsWidgets);
  });

  testWidgets('without a scope the toolbar keeps the full inset', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(400, 800),
          padding: EdgeInsets.only(top: 24, bottom: 24),
          viewPadding: EdgeInsets.only(top: 24, bottom: 24),
        ),
        child: topBarPage(),
      ),
    ));
    await tester.pumpAndSettle();

    // kToolbarHeight below the status bar, exactly as before the change.
    expect(tester.getRect(find.byType(ListView)).top, kToolbarHeight + 24);
    expect(tester.getRect(find.byType(AppBar)).top, 0);
  });
}
