import '../../components/expressive_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:hive_flutter/hive_flutter.dart';

import '../../components/cards/message_first_card.dart';
import '../../components/cards/message_header_card.dart';
import '../../components/cards/message_second_card.dart';
import '../../components/cards/message_third_card.dart';
import '../../components/expressive_list_section.dart';
import '../../components/liquid_top_bar.dart';
import '../../pages/message/message_controller.dart';
import '../../pages/noitfication/notification_page.dart';
import '../../utils/extensions.dart';
import '../../utils/global_data.dart';
import '../../logic/announcements/app_announcements.dart';
import '../../utils/storage_util.dart';

class MessagePage extends StatefulWidget {
  const MessagePage({super.key, this.scrollController});

  /// Owned by [MainPage] so the status bar tap can scroll this page back to
  /// the top; falls back to an internal controller when absent.
  final ScrollController? scrollController;

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _titleList = ['@我的动态', '@我的评论', '我收到的赞', '好友关注', '私信与信息'];
  final _iconList = [
    Icons.alternate_email,
    Icons.message_outlined,
    Icons.thumb_up_alt_outlined,
    Icons.person_add_outlined,
    Icons.mail_outline,
  ];
  late final MessageController _messageController =
      Get.put(MessageController());

  ScrollController? _ownScrollController;
  ScrollController get _scrollController =>
      widget.scrollController ??
      (_ownScrollController ??= ScrollController());

  @override
  void dispose() {
    _ownScrollController?.dispose();
    Get.delete<MessageController>();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (GlobalData().isLogin) {
      _onRefresh();
    }
  }

  Future<void> _onRefresh() async {
    if (!mounted || !GlobalData().isLogin) return;
    final generation = GlobalData().sessionGeneration;
    await _messageController.getProfile();
    if (!mounted || generation != GlobalData().sessionGeneration) return;
    await _messageController.checkCount();
  }

  Widget _shortcuts(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (GlobalData().isLogin && !GStorage.floatingNavigation) ...[
            Obx(() =>
                messageFirstCard(true, context, _messageController.firstList)),
            const SizedBox(height: 10),
          ],
          messageSeconfCard(GlobalData().isLogin, context),
        ],
      );

  Widget _messages(BuildContext context) {
    final announcements = AppAnnouncements.service;
    Widget list() => ExpressiveListSection(
          padding: EdgeInsets.zero,
          children: [
            for (var index = 0; index < _titleList.length; index++)
              Obx(() => messageThirdCard(
                    context,
                    _iconList[index],
                    _titleList[index],
                    (_messageController.thirdList.getOrNull(index) ?? 0) +
                        (index == 4 ? announcements?.unreadCount ?? 0 : 0),
                    () {
                      if (!GlobalData().isLogin && index != 4) return;
                      Get.toNamed('/notification', arguments: {
                        'type': NotificationType.values[index],
                        if (index == 4)
                          'notificationCount':
                              _messageController.notificationCount.value,
                        if (index == 4)
                          'onNotificationsRead': () =>
                              _messageController.notificationCount.value = null,
                      });
                      final count =
                          _messageController.thirdList.getOrNull(index);
                      if (count != null && count > 0) {
                        _messageController.thirdList[index] = null;
                      }
                    },
                  )),
          ],
        );
    return announcements == null
        ? list()
        : AnimatedBuilder(animation: announcements, builder: (_, __) => list());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ValueListenableBuilder(
      valueListenable: GStorage.settings.listenable(keys: [
        SettingsBoxKey.floatingNavigation,
        SettingsBoxKey.liquidGlass,
        SettingsBoxKey.liquidGlassLevel,
      ]),
      builder: (context, _, __) => LiquidTopBarScaffold(
        overlayBody: false,
        title: const Text('我的'),
        compactTitle: true,
        floatWithoutGlass: true,
        glassTitle: (_) =>
            const Align(alignment: Alignment.centerLeft, child: Text('我的')),
        glassActions: (context) => [
          for (final action in [
            (Icons.switch_account_outlined, '账号管理', '/accounts'),
            (Icons.settings_outlined, '设置', '/settings'),
          ]) ...[
            const SizedBox(width: 10),
            LiquidGlassButton(
              height: (MediaQuery.textScalerOf(context).scale(20) + 0.0)
                  .clamp(48.0, double.infinity),
              width: (MediaQuery.textScalerOf(context).scale(20) + 0.0)
                  .clamp(48.0, double.infinity),
              level: GStorage.liquidGlassLevel,
              enabled: GStorage.liquidGlass,
              tooltip: action.$2,
              onPressed: () => Get.toNamed(action.$3),
              child: Center(child: Icon(action.$1)),
            ),
          ],
        ],
        actions: [
          IconButton(
              onPressed: () => Get.toNamed('/accounts'),
              icon: const Icon(Icons.switch_account_outlined),
              tooltip: '账号管理'),
          IconButton(
              onPressed: () => Get.toNamed('/settings'),
              icon: const Icon(Icons.settings_outlined),
              tooltip: '设置'),
        ],
        body: SafeArea(
          top: false,
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: LayoutBuilder(builder: (context, bounds) {
                final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
                final header = ColoredBox(
                  color: GStorage.floatingNavigation
                      ? Colors.transparent
                      : Theme.of(context).colorScheme.surface,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                        GStorage.floatingNavigation ? 12 : 0,
                        10,
                        GStorage.floatingNavigation ? 12 : 0,
                        10),
                    child: Obx(() => MessageHeaderCard(
                          floating: GStorage.floatingNavigation,
                          userInfo: _messageController.userInfo.value,
                          counts: _messageController.firstList.toList(),
                          onLogin: () => Get.toNamed('/login'),
                        )),
                  ),
                );
                // A short landscape window must still reach the messages at
                // enlarged text sizes instead of pinning the entire viewport.
                final pinHeader = bounds.maxHeight >= 320 * scale;
                return ExpressiveRefreshIndicator(
                  onRefresh: () async {
                    if (GlobalData().isLogin) {
                      await _onRefresh();
                    } else {
                      return Future.value();
                    }
                  },
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                      if (pinHeader)
                        PinnedHeaderSliver(child: header)
                      else
                        SliverToBoxAdapter(child: header),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(10, 10, 10,
                            10 + MediaQuery.paddingOf(context).bottom),
                        sliver: SliverToBoxAdapter(child: LayoutBuilder(
                          builder: (context, constraints) {
                            final scale =
                                (MediaQuery.textScalerOf(context).scale(16) /
                                        16)
                                    .clamp(1.0, 1.5);
                            if (constraints.maxWidth >= 820 * scale) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _shortcuts(context)),
                                  const SizedBox(width: 20),
                                  Expanded(child: _messages(context)),
                                ],
                              );
                            }
                            return Column(children: [
                              _shortcuts(context),
                              const SizedBox(height: 10),
                              _messages(context),
                            ]);
                          },
                        )),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
