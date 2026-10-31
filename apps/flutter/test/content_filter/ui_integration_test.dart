import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:c001apk_flutter/components/cards/feed_card.dart';
import 'package:c001apk_flutter/components/cards/feed_reply_card.dart';
import 'package:c001apk_flutter/components/common_body.dart';
import 'package:c001apk_flutter/logic/content_filter/app_content_filter.dart';
import 'package:c001apk_flutter/logic/content_filter/content_filter_service.dart';
import 'package:c001apk_flutter/logic/model/feed/datum.dart';
import 'package:c001apk_flutter/logic/network/request.dart';
import 'package:c001apk_flutter/logic/state/loading_state.dart';
import 'package:c001apk_flutter/pages/common/common_controller.dart';
import 'package:c001apk_flutter/pages/feed/feed_page.dart';
import 'package:c001apk_flutter/pages/user/user_page.dart';
import 'package:dio/dio.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:get/get.dart';

import '../network/guest_detail_test.dart' show GuestDetailAdapter;

class _PausedController extends CommonController {
  int calls = 0;
  @override
  Future<LoadingState> customGetData() async {
    calls++;
    return LoadingState.empty();
  }
}

class _UserPageAdapter extends GuestDetailAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final user = options.uri.path == '/v6/user/space';
    return ResponseBody.fromString(
        jsonEncode({
          'data': user
              ? {
                  'uid': 1007278,
                  'username': '合成用户',
                  'cover': '',
                  'userAvatar': '',
                  'logintime': 1760000000,
                  'level': 1,
                  'feed': 20,
                  'beLikeNum': 0,
                  'fans': 0,
                  'follow': 0,
                }
              : options.queryParameters['page'] == 1
                  ? List.generate(
                      20,
                      (i) => {
                            'id': 200 + i,
                            'entityId': 'user-feed-$i',
                            'entityType': 'feed',
                            'uid': 1007278,
                            'feedTypeName': '图文',
                            'userInfo': {'uid': 1007278, 'username': '合成用户'},
                            'message': '正常技术分享 $i',
                            'message_raw_output': '[]',
                          })
                  : []
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }
}

void main() {
  late Directory temp;
  late Box<dynamic> box;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('filter-ui-');
    Hive.init(temp.path);
    GStorage.blackList = await Hive.openBox('blackList');
    GStorage.settings = await Hive.openBox('settings');
    GStorage.favFeed = await Hive.openBox('favFeed');
    await GStorage.settings.putAll({
      SettingsBoxKey.xAppDevice: 'synthetic-test-device',
      SettingsBoxKey.versionCode: '2604201',
      SettingsBoxKey.versionName: '16.2.0',
      SettingsBoxKey.apiVersion: '16',
      SettingsBoxKey.sdkInt: '33',
      SettingsBoxKey.userAgent: 'SyntheticTest/1.0',
      SettingsBoxKey.recordHistory: false,
    });
    Request();
    box = await Hive.openBox('filter');
  });
  setUp(() async {
    await box.clear();
    await GStorage.blackList.clear();
    await box.put('enabled', true);
    AppContentFilter.service = ContentFilterService(box);
  });
  tearDown(() {
    Get.reset();
    AppContentFilter.service?.dispose();
    AppContentFilter.service = null;
  });

  testWidgets(
      'detail rebuilds and restores reading position after a rule hides the page',
      (tester) async {
    final service = AppContentFilter.service!;
    const authorRule = 'author.partner-showcase.1007278';
    await tester.runAsync(() => service.setRuleDisabled(authorRule, true));
    final adapter = GuestDetailAdapter();
    adapter.apiBody = {
      'data': {
        'id': 123,
        'entityType': 'feed',
        'uid': 1007278,
        'feedTypeName': '图文',
        'userInfo': {'uid': 1007278, 'username': '合成作者'},
        'message': List.generate(50, (i) => '<p>正常技术段落 $i</p>').join(),
        'message_raw_output': '[]',
        'replynum': 0,
      }
    };
    Request.dio.httpClientAdapter = adapter;
    await tester.pumpWidget(const GetMaterialApp(home: FeedPage(id: '123')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final scroll = find.byType(CustomScrollView);
    await tester.drag(scroll, const Offset(0, -360));
    await tester.pumpAndSettle();
    final before = tester.widget<CustomScrollView>(scroll).controller!.offset;
    expect(before, greaterThan(200));
    await tester.runAsync(() => service.setRuleDisabled(authorRule, false));
    await tester.pumpAndSettle();
    expect(find.text('内容已过滤'), findsOneWidget);
    expect(scroll, findsNothing);
    await tester.runAsync(() => service.setRuleDisabled(authorRule, true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<CustomScrollView>(scroll).controller!.offset,
        closeTo(before, 1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('user page restores its list after an author rule hides it',
      (tester) async {
    final service = AppContentFilter.service!;
    const authorRule = 'author.partner-showcase.1007278';
    await tester.runAsync(() => service.setRuleDisabled(authorRule, true));
    Request.dio.httpClientAdapter = _UserPageAdapter();
    await tester.pumpWidget(GetMaterialApp(
        initialRoute: '/u/1007278',
        getPages: [GetPage(name: '/u/:uid', page: () => const UserPage())]));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final scroll = find.byType(CustomScrollView);
    await tester.drag(scroll, const Offset(0, -360));
    await tester.pumpAndSettle();
    final before = tester.widget<CustomScrollView>(scroll).controller!.offset;
    expect(before, greaterThan(200));
    await tester.runAsync(() => service.setRuleDisabled(authorRule, false));
    await tester.pumpAndSettle();
    expect(find.text('内容已过滤'), findsOneWidget);
    expect(scroll, findsNothing);
    await tester.runAsync(() => service.setRuleDisabled(authorRule, true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<CustomScrollView>(scroll).controller!.offset,
        closeTo(before, 1));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  Future<void> mount(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))));
    await tester.pump();
  }

  Finder visibleText(String text) => find.byWidgetPredicate((widget) =>
      widget is Text &&
          (widget.data ?? widget.textSpan?.toPlainText() ?? '')
              .contains(text) ||
      widget is RichText && widget.text.toPlainText().contains(text));

  testWidgets(
      'normal feed stays visible while blocked hot reply has no text or image target',
      (tester) async {
    await mount(
        tester,
        FeedCard(
            data: Datum(
                entityType: 'feed',
                id: 1,
                uid: 7,
                message: '正常刷机正文',
                replyRows: [
              Datum(
                  id: 2,
                  uid: 1007278,
                  message: '不应展示的热评',
                  picArr: ['https://example.invalid/hidden.png'])
            ])));
    expect(visibleText('正常刷机正文'), findsWidgets);
    expect(visibleText('不应展示的热评'), findsNothing);
    expect(visibleText('查看图片'), findsNothing);
    expect(find.text('仅本次查看'), findsOneWidget);
  });

  testWidgets(
      'hidden parent retains normal reply and more replies without matching ruid',
      (tester) async {
    await mount(
        tester,
        FeedReplyCard(
            data: Datum(
                entityType: 'feed_reply',
                id: 2,
                uid: 1007278,
                message: '父评论私密文本',
                replyRowsMore: 1,
                replynum: 3,
                replyRows: [
              Datum(id: 3, uid: 8, ruid: 1007278, message: '正常回复仍可阅读')
            ])));
    expect(visibleText('父评论私密文本'), findsNothing);
    expect(visibleText('正常回复仍可阅读'), findsWidgets);
    expect(find.text('查看更多回复(3)'), findsOneWidget);
  });

  testWidgets('forward reveal is independent from parent and nested hot reply',
      (tester) async {
    await mount(
        tester,
        FeedCard(
            data: Datum(
                entityType: 'feed',
                id: 1,
                uid: 7,
                message: '普通转发说明',
                forwardSourceType: 'feed',
                forwardSourceFeed:
                    Datum(id: 4, uid: 1007278, message: '隐藏原帖正文'),
                replyRows: [Datum(id: 5, uid: 1007278, message: '隐藏热评正文')])));
    expect(visibleText('普通转发说明'), findsWidgets);
    expect(visibleText('隐藏原帖正文'), findsNothing);
    await tester.tap(find.text('仅本次查看').first);
    await tester.pump();
    expect(visibleText('隐藏原帖正文'), findsWidgets);
    expect(visibleText('隐藏热评正文'), findsNothing);
  });

  testWidgets('quoted text is sanitized and can be revealed independently',
      (tester) async {
    await mount(
        tester,
        FeedCard(
            data: Datum(
                entityType: 'feed',
                id: 9,
                uid: 7,
                message: '<blockquote>想操她</blockquote>请保持正常讨论')));
    expect(visibleText('请保持正常讨论'), findsWidgets);
    expect(visibleText('想操她'), findsNothing);
    await tester.tap(find.text('仅本次查看引用'));
    await tester.pump();
    expect(visibleText('想操她'), findsWidgets);
    expect(AppContentFilter.service!.allowedContentKeys, isEmpty);
  });

  for (final replies in [false, true]) {
    testWidgets(
        'paused automatic loading stays paused and manual retry loads (replies: $replies)',
        (tester) async {
      final controller = _PausedController()
        ..automaticLoadPaused = true
        ..footerState.value = LoadingState.error('点击继续加载')
        ..loadingState.value = LoadingState.success(<Datum>[]);
      await tester.pumpWidget(MaterialApp(
          home:
              Scaffold(body: commonBody(controller, isReply2Reply: replies))));
      await tester.pump();
      expect(controller.calls, 0);
      expect(find.text('点击继续加载'), findsOneWidget);
      await tester.tap(find.text('点击继续加载'));
      await tester.pump();
      expect(controller.calls, 1);
      controller.onClose();
    });
  }

  for (final width in [393.0, 1280.0]) {
    testWidgets(
        'list silently filters and restores cached rows at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 873);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _PausedController()
        ..isEnd = true
        ..scrollController = ScrollController();
      controller.publishItems([
        Datum(entityType: 'feed', id: 7, uid: 1007278, message: '应静默隐藏'),
        Datum(entityType: 'feed', id: 8, uid: 7, message: '正常内容仍可见'),
      ]);
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 873),
                  padding: const EdgeInsets.only(top: 40)),
              child: Scaffold(
                  body: commonBody(controller,
                      itemBuilder: (item) => Text(item.message!))))));
      await tester.pumpAndSettle();
      expect(controller.filteredItems, hasLength(1));
      expect(find.text('应静默隐藏'), findsNothing);
      expect(find.text('正常内容仍可见'), findsOneWidget);
      expect(find.textContaining('已过滤'), findsNothing);
      expect(find.textContaining('查看原因'), findsNothing);
      expect(find.byIcon(Icons.filter_alt_outlined), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      final scroll = controller.scrollController;
      expect(scroll!.hasClients, isTrue);
      await tester.runAsync(() => AppContentFilter.service!.setEnabled(false));
      await tester.pumpAndSettle();
      expect(find.text('应静默隐藏'), findsOneWidget);
      expect(identical(controller.scrollController, scroll), isTrue);
      expect(controller.calls, 0);
      expect(AppContentFilter.service!.allowedContentKeys, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      scroll.dispose();
      controller.onClose();
    });
  }
}
