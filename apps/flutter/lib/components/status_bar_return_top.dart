import 'dart:io';

import 'package:flutter/material.dart';

/// Routes a tap on the iOS status bar strip (the Dynamic Island) to the
/// scrolling page the user is looking at.
///
/// On iOS, the native embedder catches taps on the status bar and Dynamic
/// Island through UIKit's `scrollsToTop` mechanism, which Flutter exposes via
/// [WidgetsBindingObserver.handleStatusBarTap]. On other platforms, or when a
/// tap lands directly on the safe-area strip, [StatusBarTapDetector] catches it.
///
/// This deliberately never asks the scroll chrome to come back: `scroll_chrome`
/// documents that a tap must not restore the toolbars, only a sustained upward
/// drag does.
class StatusBarReturnTop {
  StatusBarReturnTop._();

  static final List<_StatusBarBinding> _bindings = [];
  static bool _installed = false;
  static DateTime _lastDispatch = DateTime.fromMillisecondsSinceEpoch(0);
  static final _StatusBarObserver _observer = _StatusBarObserver();

  /// Registers [onTap] for [owner], replacing any previous registration.
  ///
  /// [isActive] lets a page that stays alive behind another route (a kept-alive
  /// tab, an offstage reading pane detail) step aside. It is evaluated when the
  /// tap happens, never during registration.
  static void bind(
    Object owner,
    VoidCallback onTap, {
    bool Function()? isActive,
  }) {
    install();
    unbind(owner);
    _bindings.add(_StatusBarBinding(owner, onTap, isActive));
  }

  static void unbind(Object owner) {
    _bindings.removeWhere((binding) => binding.owner == owner);
  }

  /// Runs the most recently bound handler that reports itself active.
  ///
  /// Newest wins because pages stay mounted behind the visible one, and the
  /// most recently opened page is the one on screen.
  static void dispatch() {
    final now = DateTime.now();
    if (now.difference(_lastDispatch) < const Duration(milliseconds: 300)) {
      return;
    }
    _lastDispatch = now;

    for (var index = _bindings.length - 1; index >= 0; index--) {
      final binding = _bindings[index];
      if (binding.isActive?.call() == false) continue;
      binding.onTap();
      return;
    }
  }

  /// Hooks the status bar tap observer. Safe to call more than once.
  static void install() {
    if (_installed) return;
    _installed = true;
    WidgetsBinding.instance.addObserver(_observer);
  }

  @visibleForTesting
  static void clear() {
    _bindings.clear();
    _lastDispatch = DateTime.fromMillisecondsSinceEpoch(0);
  }
}

class _StatusBarObserver with WidgetsBindingObserver {
  @override
  void handleStatusBarTap() {
    StatusBarReturnTop.dispatch();
  }
}

class _StatusBarBinding {
  const _StatusBarBinding(this.owner, this.onTap, this.isActive);

  final Object owner;
  final VoidCallback onTap;
  final bool Function()? isActive;
}

/// Registers a page's [onStatusBarReturnTop] for as long as it is the route on
/// screen, and drops the registration when the page goes away.
///
/// A page kept alive behind another route stays mounted, so the binding also
/// asks the route whether it is still current; otherwise the tab the user left
/// would answer a tap meant for the page they opened.
mixin StatusBarReturnTopBinding<T extends StatefulWidget> on State<T> {
  bool _statusBarBound = false;

  void onStatusBarReturnTop();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_statusBarBound) return;
    _statusBarBound = true;
    final route = ModalRoute.of(context);
    StatusBarReturnTop.bind(
      this,
      onStatusBarReturnTop,
      // Kept pages stay mounted, so the binding has to answer "am I the one on
      // screen" at tap time. The route covers pushed pages; TickerMode and
      // Offstage cover what the reading pane parks instead of disposing,
      // since it hides inactive panes that way.
      isActive: () {
        if (!mounted || !(route?.isCurrent ?? true)) return false;
        if (_isAncestorOffstage(context)) return false;
        return TickerMode.of(context);
      },
    );
  }

  @override
  void dispose() {
    StatusBarReturnTop.unbind(this);
    super.dispose();
  }
}

bool _isAncestorOffstage(BuildContext context) {
  var offstage = false;
  context.visitAncestorElements((element) {
    if (element.widget is Offstage && (element.widget as Offstage).offstage) {
      offstage = true;
      return false;
    }
    return true;
  });
  return offstage;
}

/// Transparent hit target over the status bar strip.
///
/// Drop it as the last child of the root [Stack] so it covers every route.
///
/// Handles tap events delivered directly inside the application bounds over
/// the top safe area. [enabled] overrides the platform check for tests.
class StatusBarTapDetector extends StatefulWidget {
  const StatusBarTapDetector({super.key, this.enabled});

  final bool? enabled;

  @override
  State<StatusBarTapDetector> createState() => _StatusBarTapDetectorState();
}

class _StatusBarTapDetectorState extends State<StatusBarTapDetector> {
  @override
  void initState() {
    super.initState();
    StatusBarReturnTop.install();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final enabled = widget.enabled ?? (Platform.isAndroid || Platform.isIOS);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: top <= 0 ? 0 : top,
      child: !enabled || top <= 0
          ? const SizedBox.shrink()
          : GestureDetector(
              key: const ValueKey('status-bar-return-top'),
              // Opaque so the tap lands here instead of on whatever the page
              // painted under the status bar.
              behavior: HitTestBehavior.opaque,
              onTap: StatusBarReturnTop.dispatch,
              child: const SizedBox.expand(),
            ),
    );
  }
}
