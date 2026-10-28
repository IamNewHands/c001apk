import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../pages/home/return_top_controller.dart';
import '../../pages/home/home_page.dart';
import '../../pages/main/main_controller.dart';
import '../../pages/message/message_page.dart';
import '../local_follow/local_follow_page.dart';
import '../../logic/accounts/account_store.dart';
import '../../components/adaptive_reading_pane.dart';
import '../../components/app_navigation_history.dart';
import '../../components/feed_reading_pane.dart';
import '../../components/adaptive_main_scaffold.dart';
import '../../components/expressive_loading_indicator.dart';
import '../../components/home_publish_action.dart';
import '../../components/scroll_hiding_action.dart';
import '../../utils/global_data.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage>
    with SingleTickerProviderStateMixin {
  /// Destination order is 主页 / 关注 / 我的.
  static const int _profileDestination = 2;

  bool _homeFeedSelected = true;
  late final _publishAnimation = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300), value: 1);
  final ReturnTopController _pageScrollController =
      Get.put(ReturnTopController(), tag: 'home');
  int _selectedIndex = 0;
  final _indexSctream = StreamController<int>.broadcast();
  late final MainController _mainController = Get.put(MainController());
  var _contrller = PageController();
  bool _resetting = false;
  final _readingKey = GlobalKey<AdaptiveReadingPaneState>();

  @override
  void initState() {
    super.initState();
    _mainController.checkLoginInfo();
    AccountStore.changes.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (!mounted || _resetting) return;
    setState(() => _resetting = true);
    // Unmount old account pages for a complete frame before reusing the
    // existing Get controller tags. Routes containing old account data close.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Get.until((route) => route.isFirst);
      _contrller.dispose();
      _contrller = PageController(initialPage: _selectedIndex);
      setState(() => _resetting = false);
      _homeFeedSelected = true;
      _publishAnimation.value = 1;
      _mainController.checkLoginInfo();
    });
  }

  @override
  void dispose() {
    AccountStore.changes.removeListener(_sessionChanged);
    _indexSctream.close();
    _contrller.dispose();
    _publishAnimation.dispose();
    Get.delete<ReturnTopController>(tag: 'home');
    Get.delete<MainController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // All destinations retain their root route and existing page controllers.
    return _resetting
        ? const Scaffold(body: Center(child: ExpressiveLoadingIndicator()))
        : StreamBuilder<int>(
            initialData: _selectedIndex,
            stream: _indexSctream.stream,
            builder: (_, snapshot) => AdaptiveMainScaffold(
              selectedIndex: snapshot.data!,
              // 「我的」is not a scrolling feed, so it keeps the chrome fixed.
              autoHideChrome: snapshot.data != _profileDestination,
              railTrailing: GlobalData().isLogin &&
                      snapshot.data == 0 &&
                      _homeFeedSelected
                  ? ScrollHidingAction(
                      animation: _publishAnimation,
                      child: const HomePublishAction(extended: true))
                  : null,
              onDestinationSelected: onDestinationSelected,
              bodyBuilder: (context, useRail) => FeedReadingPane(
                paneKey: _readingKey,
                leadingInset: useRail ? 80 : 0,
                child: PageView(
                  physics: const NeverScrollableScrollPhysics(),
                  controller: _contrller,
                  children: [
                    HomePage(
                      useRail: useRail,
                      onFeedSelected: (selected) {
                        if (_homeFeedSelected != selected) {
                          setState(() => _homeFeedSelected = selected);
                        }
                      },
                      onPublishVisibilityChanged: (visible) {
                        if (visible) {
                          _publishAnimation.forward();
                        } else {
                          _publishAnimation.reverse();
                        }
                      },
                    ),
                    const FollowFeedPage(),
                    const MessagePage(),
                  ],
                ),
              ),
            ),
          );
  }

  void onDestinationSelected(int index) {
    if (_resetting || !_contrller.hasClients) return;
    AppNavigationHistoryScope.maybeOf(context)?.discardForward();
    _readingKey.currentState?.reset();
    if (index == 0 && _selectedIndex == 0) {
      _pageScrollController.setIndex(998);
    } else if (index == 1 && _selectedIndex == 1) {
      _pageScrollController.setIndex(TabType.FOLLOW.index);
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _contrller.jumpToPage(index);
    } else {
      _contrller.animateToPage(
        index,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubicEmphasized,
      );
    }
    _selectedIndex = index;
    _indexSctream.add(index);
  }
}
