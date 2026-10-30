import 'dart:io';
import 'dart:typed_data';

import 'package:c001apk_flutter/constants/home_tab.dart';
import 'package:c001apk_flutter/components/liquid_navigation_bar.dart';
import 'package:c001apk_flutter/logic/network/request.dart';
import 'package:c001apk_flutter/logic/model/feed/datum.dart';
import 'package:c001apk_flutter/pages/home/home_page.dart';
import 'package:c001apk_flutter/pages/home/home_tabs_page.dart';
import 'package:c001apk_flutter/pages/home/feed/home_feed_page.dart';
import 'package:c001apk_flutter/pages/home/feed/home_feed_controller.dart';
import 'package:c001apk_flutter/pages/home/return_top_controller.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

class _EmptyTransport implements HttpClientAdapter {
  int requests = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests++;
    return ResponseBody.fromString('{"data":[]}', 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory temp;
  late _EmptyTransport transport;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('home-tabs-');
    Hive.init(temp.path);
    GStorage.settings = await Hive.openBox('settings');
    GStorage.blackList = await Hive.openBox('blackList');
    Request();
  });
  setUp(() async {
    await GStorage.settings.clear();
    await GStorage.settings.putAll({
      SettingsBoxKey.xAppDevice: 'synthetic-tabs-device',
      SettingsBoxKey.floatingNavigation: false,
    });
    transport = _EmptyTransport();
    Request.dio.httpClientAdapter = transport;
    Get.testMode = true;
  });
  tearDown(Get.reset);
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  test('old, malformed, duplicate, and unsupported configuration is normalized',
      () {
    for (final value in [
      null,
      42,
      'bad',
      {'order': true}
    ]) {
      expect(HomeTabConfiguration.fromStored(value).order,
          HomeTabConfiguration.defaultOrder);
    }
    final config = HomeTabConfiguration.fromStored({
      'order': ['coolpic', 'coolpic', 'future', 1, 'feed'],
      'hidden': ['feed', 'hot', 'future'],
    });
    expect(config.visible(android: false),
        [TabType.COOLPIC, TabType.FEED, TabType.TOPIC, TabType.PRODUCT]);
    expect(config.available(android: false), isNot(contains(TabType.APP)));
    expect(config.available(android: true), contains(TabType.APP));
    expect(
        HomeTabConfiguration.fromStored(config.toStored()).order, config.order);
    expect(HomeTabConfiguration.fromStored(config.toStored()).hidden,
        config.hidden);
  });

  Future<void> mountEditor(WidgetTester tester,
      {double width = 400, double scale = 1}) async {
    await tester.binding.setSurfaceSize(Size(width, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => MediaQuery(
                            data: MediaQueryData(
                                textScaler: TextScaler.linear(scale)),
                            child: const HomeTabsPage()),
                      )),
                  child: const Text('编辑')))),
    ));
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'editing is a draft, cancel keeps preferences, done persists across reopen',
      (tester) async {
    await mountEditor(tester);
    final hot = find.byKey(const ValueKey(TabType.HOT));
    await tester.tap(find.descendant(of: hot, matching: find.byType(Checkbox)));
    await tester.tap(find.byTooltip('上移热门'));
    expect(GStorage.settings.get(HomeTabConfiguration.storageKey), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Checkbox>(
                find.descendant(of: hot, matching: find.byType(Checkbox)))
            .value,
        isTrue);
    await tester.tap(find.descendant(of: hot, matching: find.byType(Checkbox)));
    await tester.tap(find.byTooltip('上移热门'));
    await tester.runAsync(() async {
      await tester.tap(find.text('完成'));
      await GStorage.settings.flush();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await GStorage.settings.flush();
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Checkbox>(
                find.descendant(of: hot, matching: find.byType(Checkbox)))
            .value,
        isFalse);
    final feed = find.byKey(const ValueKey(TabType.FEED));
    expect(
        tester
            .widget<Checkbox>(
                find.descendant(of: feed, matching: find.byType(Checkbox)))
            .onChanged,
        isNull);
    await tester.tap(find.text('恢复默认'));
    await tester.runAsync(() async {
      await tester.tap(find.text('完成'));
      await GStorage.settings.flush();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(
        HomeTabConfiguration.fromStored(
                GStorage.settings.get(HomeTabConfiguration.storageKey))
            .hidden,
        isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'editor fits 320 wide at large text and supports a single visible category',
      (tester) async {
    await mountEditor(tester, width: 320, scale: 1.7);
    for (final tab in HomeTabConfiguration.defaultOrder
        .where((tab) => tab != TabType.FEED && tab != TabType.APP)) {
      final checkbox = find.descendant(
          of: find.byKey(ValueKey(tab)), matching: find.byType(Checkbox));
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
    }
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      await tester.tap(find.text('完成'));
      await GStorage.settings.flush();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(
        HomeTabConfiguration.fromStored(
                GStorage.settings.get(HomeTabConfiguration.storageKey))
            .visible(android: false),
        [TabType.FEED]);
    await tester.pumpWidget(const SizedBox());
  });

  for (final floating in [false, true]) {
    testWidgets(
        'reorder preserves page, scroll and selection (floating: $floating)',
        (tester) async {
      await tester.runAsync(() =>
          GStorage.settings.put(SettingsBoxKey.floatingNavigation, floating));
      Get.put(ReturnTopController(), tag: 'home');
      final selections = <bool>[];
      await tester.pumpWidget(
          GetMaterialApp(home: HomePage(onFeedSelected: selections.add)));
      await tester.pumpAndSettle();
      final page = find.byWidgetPredicate(
          (w) => w is HomeFeedPage && w.tabType == TabType.FEED);
      final state = tester.state(page);
      final controller = Get.find<HomeFeedController>(tag: 'FEED');
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      controller.publishItems(List.generate(
          30,
          (i) => Datum(
                id: 'synthetic-$i',
                entityType: 'feed',
                uid: '123',
                username: '测试用户',
                message: '离线测试内容 $i',
                dateline: 1700000000,
              )));
      await tester.pumpAndSettle();
      controller.scrollController!.jumpTo(250);
      await tester.pumpAndSettle();
      final scroll = controller.scrollController;
      await tester.tap(find.byTooltip('编辑主页分类'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('上移热门'));
      await tester.runAsync(() async {
        await tester.tap(find.text('完成'));
        await GStorage.settings.flush();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(tester.state(page), same(state));
      expect(Get.find<HomeFeedController>(tag: 'FEED'), same(controller));
      expect(controller.scrollController, same(scroll));
      expect(controller.scrollController!.offset, 250);
      if (floating) {
        expect(
            tester
                .widget<LiquidNavigationBar>(find.byType(LiquidNavigationBar))
                .selectedIndex,
            1);
      } else {
        expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
      }
      await tester.tapAt(tester.getCenter(find.text('热门').first));
      await tester.pumpAndSettle();
      expect(selections.last, isFalse);
      await tester.tap(find.byTooltip('编辑主页分类'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey(TabType.HOT)),
          matching: find.byType(Checkbox)));
      await tester.runAsync(() async {
        await tester.tap(find.text('完成'));
        await GStorage.settings.flush();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(selections.last, isTrue);
      expect(find.text('热门'), findsNothing);
      expect(tester.state(page), same(state));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('failed save stays in editor and allows another attempt',
      (tester) async {
    await mountEditor(tester);
    await tester.runAsync(() => GStorage.settings.close());
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.runAsync(() async {
        await tester.tap(find.text('完成'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(find.text('保存失败，请重试'), findsOneWidget);
      expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, '完成'))
              .onPressed,
          isNotNull);
    }
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HomeTabsPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
