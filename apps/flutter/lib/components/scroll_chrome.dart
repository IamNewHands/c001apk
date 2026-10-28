import 'package:flutter/material.dart';

/// Hides the main chrome while the user scrolls down and restores it on
/// scroll-up, on tap, or shortly after the scroll settles.
///
/// One controller drives both the top toolbar and the bottom navigation so the
/// two surfaces cannot disagree, and so the body inset can interpolate with the
/// same value that moves them.
class ScrollChromeController extends ChangeNotifier {
  ScrollChromeController({required TickerProvider vsync})
      : _animation = AnimationController(
          vsync: vsync,
          duration: animationDuration,
          value: 1,
        ),
        _hold = AnimationController(vsync: vsync, duration: settleDelay) {
    _animation.addListener(notifyListeners);
    // The idle delay is a ticker, not a [Timer]: a pending timer outlives the
    // widget tree and fails widget tests, and a ticker also lets
    // `pumpAndSettle` drive the restore to completion.
    _hold.addStatusListener((status) {
      if (status == AnimationStatus.completed) show();
    });
  }

  /// Long enough to read as a slide, short enough to feel attached to the
  /// gesture.
  static const Duration animationDuration = Duration(milliseconds: 200);

  /// A short flick must not leave the bars hidden, so the chrome returns once
  /// the scroll has been idle for this long.
  static const Duration settleDelay = Duration(milliseconds: 500);

  final AnimationController _animation;
  final AnimationController _hold;

  /// 1 = fully shown, 0 = fully hidden.
  double get progress => _animation.value;

  bool get hidden => _animation.value < 1;

  void hide() {
    cancelSettle();
    if (_animation.value == 0) return;
    _animation.animateTo(0, curve: Curves.easeInOutCubicEmphasized);
  }

  void show() {
    cancelSettle();
    if (_animation.value == 1) return;
    _animation.animateTo(1, curve: Curves.easeInOutCubicEmphasized);
  }

  /// Restore once the scroll has been idle for [settleDelay].
  void settle() {
    cancelSettle();
    // A scroll often ends in the same frame that hid the chrome, so the
    // animation still reads 1 here; only skip when nothing is moving.
    if (_animation.value == 1 && !_animation.isAnimating) return;
    _hold.forward(from: 0);
  }

  /// Cancels a pending [settle] without changing the current state.
  void cancelSettle() {
    if (_hold.isAnimating) _hold.stop();
  }

  @override
  void dispose() {
    _animation.removeListener(notifyListeners);
    _hold.dispose();
    _animation.dispose();
    super.dispose();
  }
}

/// Publishes the chrome controller plus the per-surface freeze switches.
///
/// The bottom surface is frozen on wide layouts, where a rail replaces the bar;
/// the top surface is frozen only while the keyboard owns the screen. A frozen
/// surface always reports full progress, so the body inset matches the layout
/// that is actually on screen.
class ScrollChromeScope extends InheritedNotifier<ScrollChromeController> {
  const ScrollChromeScope({
    super.key,
    required ScrollChromeController controller,
    required this.topFrozen,
    required this.bottomFrozen,
    required super.child,
  }) : super(notifier: controller);

  final bool topFrozen, bottomFrozen;

  static ScrollChromeController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ScrollChromeScope>()
      ?.notifier;

  /// Effective progress for the top toolbar; 1 outside a [ScrollChromeScope].
  static double topProgressOf(BuildContext context) =>
      _progressOf(context, true);

  /// Effective progress for the bottom navigation and the body inset.
  static double bottomProgressOf(BuildContext context) =>
      _progressOf(context, false);

  static double _progressOf(BuildContext context, bool top) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ScrollChromeScope>();
    if (scope == null) return 1;
    if (top ? scope.topFrozen : scope.bottomFrozen) return 1;
    return scope.notifier?.progress ?? 1;
  }

  @override
  bool updateShouldNotify(covariant ScrollChromeScope oldWidget) =>
      super.updateShouldNotify(oldWidget) ||
      oldWidget.topFrozen != topFrozen ||
      oldWidget.bottomFrozen != bottomFrozen;
}

/// Slides one chrome surface out of the way and stops it from taking taps.
///
/// A fractional translation keeps the element tree and the layout slot intact,
/// so a feed keeps its scroll position while the bars come and go.
class ScrollChromeHide extends StatelessWidget {
  const ScrollChromeHide({
    super.key,
    required this.child,
    required this.top,
  });

  final Widget child;

  /// Top chrome leaves upward, bottom chrome leaves downward.
  final bool top;

  @override
  Widget build(BuildContext context) {
    final progress = top
        ? ScrollChromeScope.topProgressOf(context)
        : ScrollChromeScope.bottomProgressOf(context);
    final slide = 1 - progress;
    return FractionalTranslation(
      translation: Offset(0, top ? -slide : slide),
      // Hit testing follows the untranslated slot; [IgnorePointer] is what
      // actually stops taps once the surface starts to leave.
      transformHitTests: false,
      child: IgnorePointer(ignoring: slide > 0, child: child),
    );
  }
}

/// Hides the chrome while the scrollable below it moves down and brings it back
/// on the way up.
///
/// It stays out of the layout: it only feeds the [ScrollChromeController] and
/// hands the constraints down untouched.
class ScrollChromeHost extends StatefulWidget {
  const ScrollChromeHost({
    super.key,
    required this.controller,
    required this.enabled,
    required this.child,
  });

  final ScrollChromeController controller;

  /// False disables auto-hide; the controller is left untouched so a caller can
  /// still drive it.
  final bool enabled;
  final Widget child;

  /// Same-direction travel needed before the state flips. Touch drags deliver
  /// only a few pixels per frame, so this is accumulated, not per event.
  static const double switchThreshold = 12;

  @override
  State<ScrollChromeHost> createState() => _ScrollChromeHostState();
}

class _ScrollChromeHostState extends State<ScrollChromeHost> {
  double _accumulated = 0;

  bool _onNotification(ScrollNotification notification) {
    if (!widget.enabled) {
      _accumulated = 0;
      return false;
    }
    if (notification is ScrollStartNotification) {
      widget.controller.cancelSettle();
      _accumulated = 0;
    } else if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta;
      // A horizontal pager must not toggle the chrome of the vertical feed.
      if (delta == null ||
          delta == 0 ||
          notification.metrics.axis != Axis.vertical) {
        return false;
      }
      _accumulated =
          delta.sign == _accumulated.sign ? _accumulated + delta : delta;
      if (_accumulated > ScrollChromeHost.switchThreshold) {
        _accumulated = 0;
        widget.controller.hide();
      } else if (_accumulated < -ScrollChromeHost.switchThreshold) {
        _accumulated = 0;
        widget.controller.show();
      }
    } else if (notification is ScrollEndNotification) {
      _accumulated = 0;
      widget.controller.settle();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(
        onNotification: _onNotification,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          // Tapping the content is the manual way back to a full bar. The
          // gesture arena keeps taps on cards and buttons with the child.
          onTap: widget.enabled ? widget.controller.show : null,
          child: widget.child,
        ),
      );
}
