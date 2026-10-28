import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../utils/storage_util.dart';
import 'expressive_navigation_bar.dart';
import 'liquid_navigation_bar.dart';
import 'scroll_chrome.dart';

/// The page subtree stays in the same slot when navigation style or width changes.
class AdaptiveMainScaffold extends StatefulWidget {
  const AdaptiveMainScaffold({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.bodyBuilder,
    this.railTrailing,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget Function(BuildContext context, bool useRail) bodyBuilder;
  final Widget? railTrailing;

  @override
  State<AdaptiveMainScaffold> createState() => _AdaptiveMainScaffoldState();
}

class _AdaptiveMainScaffoldState extends State<AdaptiveMainScaffold>
    with TickerProviderStateMixin {
  late final ScrollChromeController _chrome =
      ScrollChromeController(vsync: this);

  @override
  void didUpdateWidget(AdaptiveMainScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Switching tabs lands the user on new content: never leave them without
    // the way back. Deferred because this runs inside the build phase.
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _chrome.show();
      });
    }
  }

  @override
  void dispose() {
    _chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: GStorage.settings.listenable(keys: [
          SettingsBoxKey.floatingNavigation,
          SettingsBoxKey.liquidGlass,
          SettingsBoxKey.liquidGlassLevel,
          SettingsBoxKey.scrollChromeAutoHide,
        ]),
        builder: (context, _, __) =>
            LayoutBuilder(builder: (context, constraints) {
          final outerPadding = MediaQuery.paddingOf(context);
          final useRail =
              constraints.maxWidth - outerPadding.horizontal >= 600;
          // Scaffold zeroes viewPadding for its body, so the safe inset has to
          // be read above it.
          final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
          final floating = GStorage.floatingNavigation;
          final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
          // The rail never hides and the keyboard owns the screen, so only the
          // surfaces that can actually leave stay reachable.
          final frozen = keyboard || !GStorage.scrollChromeAutoHide;
          if (frozen && _chrome.hidden) {
            // A frozen surface reports full progress; drop the stale animation
            // value too so unfreezing cannot snap the bars back out.
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _chrome.show());
          }
          return ScrollChromeScope(
            controller: _chrome,
            topFrozen: frozen,
            bottomFrozen: frozen || useRail,
            child: ScrollChromeHost(
              controller: _chrome,
              enabled: !frozen,
              child: Scaffold(
                // Scaffold inserts a different element tree when extendBody changes.
                // Keep it enabled and reserve the standard bar with stable wrappers so
                // preference/width changes cannot unmount account pages or their scrolls.
                extendBody: true,
                body: Builder(builder: (context) {
                  final media = MediaQuery.of(context);
                  final reserve = !useRail && !keyboard && !floating;
                  // extendBody hands the body a bottom padding that already covers
                  // the bar and the safe area; collapse it to the safe area only.
                  final progress =
                      ScrollChromeScope.bottomProgressOf(context);
                  final bottom = media.padding.bottom;
                  // extendBody adds the bar height on top of the safe area; keep
                  // the safe area and slide only the bar's own share away.
                  final share = bottom - safeBottom;
                  final inset =
                      share <= 0 ? bottom : safeBottom + share * progress;
                  return Padding(
                    padding: EdgeInsets.only(bottom: reserve ? inset : 0),
                    child: MediaQuery(
                      data: media.copyWith(
                        padding: reserve
                            ? media.padding.copyWith(bottom: 0)
                            : media.padding.copyWith(bottom: inset),
                        // Nested page FABs use viewPadding; lists use padding.
                        viewPadding: !useRail && floating && !keyboard
                            ? media.viewPadding
                                .copyWith(bottom: media.padding.bottom)
                            : media.viewPadding,
                      ),
                      child: SafeArea(
                        top: false,
                        bottom: false,
                        child: Row(children: [
                          SizedBox(
                            width: useRail ? 80 : 0,
                            child: Offstage(
                              offstage: !useRail,
                              child: NavigationRail(
                                trailingAtBottom: true,
                                trailing: widget.railTrailing == null
                                    ? null
                                    : Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 16),
                                        child: widget.railTrailing,
                                      ),
                                selectedIndex: widget.selectedIndex,
                                onDestinationSelected:
                                    widget.onDestinationSelected,
                                labelType: NavigationRailLabelType.all,
                                destinations: const [
                                  NavigationRailDestination(
                                      icon: Icon(Icons.home_outlined),
                                      selectedIcon: Icon(Icons.home),
                                      label: Text('主页')),
                                  NavigationRailDestination(
                                      icon: Icon(Icons.feed_outlined),
                                      selectedIcon: Icon(Icons.feed),
                                      label: Text('关注')),
                                  NavigationRailDestination(
                                      icon: Icon(Icons.person_outline),
                                      selectedIcon: Icon(Icons.person),
                                      label: Text('我的')),
                                ],
                              ),
                            ),
                          ),
                          Expanded(child: widget.bodyBuilder(context, useRail)),
                        ]),
                      ),
                    ),
                  );
                }),
                bottomNavigationBar: useRail || keyboard
                    ? null
                    : ScrollChromeHide(
                        top: false,
                        child: floating
                            ? LiquidNavigationBar(
                                selectedIndex: widget.selectedIndex,
                                onDestinationSelected:
                                    widget.onDestinationSelected,
                                refract: GStorage.liquidGlass,
                                level: GStorage.liquidGlassLevel,
                              )
                            : ExpressiveNavigationBar(
                                selectedIndex: widget.selectedIndex,
                                onDestinationSelected:
                                    widget.onDestinationSelected,
                              ),
                      ),
              ),
            ),
          );
        }),
      );
}
