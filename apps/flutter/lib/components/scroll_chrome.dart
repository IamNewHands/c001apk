import 'package:flutter/material.dart';

/// Hides the main chrome while the user scrolls down and restores it on a
/// deliberate scroll-up, on a tap, or on a return to the top of the feed.
///
/// Resting the scroll never brings the chrome back: a reader who stops to look
/// at a card keeps the whole screen, and the bars only return on an explicit
/// gesture.
///
/// The thresholds are asymmetric and the directions are locked after a flip, so
/// nudging a long post up and down cannot make the bars flicker in and out: a
/// small upward move is just more of the same post, not a request for the bars.
///
/// One controller drives both the top toolbar and the bottom navigation so the
/// two surfaces cannot disagree, and so the body inset can interpolate with the
/// same value that moves them.
class ScrollChromeController extends ChangeNotifier {
  ScrollChromeController({required TickerProvider vsync})
      : _animation = AnimationController(
          vsync: vsync,
          duration: hideDuration,
          value: 1,
        ),
        _delay = AnimationController(vsync: vsync, duration: showDelay),
        _lock = AnimationController(vsync: vsync, duration: lockDuration) {
    _animation.addListener(notifyListeners);
    _delay.addStatusListener(_onShowDelayStatus);
  }

  /// Hiding follows the finger, so it stays quick.
  static const Duration hideDuration = Duration(milliseconds: 200);

  /// Coming back is a deliberate gesture, so the slide can breathe.
  static const Duration showDuration = Duration(milliseconds: 240);

  /// Downward travel that hides the chrome.
  static const double hideThreshold = 16;

  /// Upward travel that brings it back: more than four times the hide
  /// threshold, so only a real scroll-up counts.
  static const double showThreshold = 72;

  /// The finger has to stay on the screen and travel up for this long, without
  /// interruption, before the chrome returns. A short flick up to re-read one
  /// line is not a request for the bars, and neither is the momentum that
  /// carries the feed on after the finger leaves.
  static const Duration showDelay = Duration(seconds: 2);

  /// The opposite direction is ignored for this long after a flip, so a flip
  /// always finishes its animation instead of being reversed mid-slide.
  static const Duration lockDuration = Duration(milliseconds: 400);

  final AnimationController _animation, _delay, _lock;

  double _down = 0, _up = 0;
  bool _revealPending = false;
  bool _leaving = false;

  /// 1 = fully shown, 0 = fully hidden.
  double get progress => _animation.value;

  bool get hidden => _animation.value < 1;

  /// True while a flip is settling; frames in the other direction are dropped
  /// so the animation is never cut in half.
  bool get locked => _lock.isAnimating;

  /// True while the chrome is on its way out.
  ///
  /// Tracked by hand because [AnimationController.status] does not report the
  /// direction of a curved [AnimationController.animateTo] reliably.
  bool get hiding => _leaving;

  /// Feeds one vertical scroll frame that carries the reader further down the
  /// feed.
  ///
  /// Only hiding comes from the scroll physics. Momentum is welcome to finish
  /// taking the bars away, but it can never bring them back: the reveal is
  /// driven by the finger itself, through [pointerMoved], so no amount of
  /// coasting, bouncing or clamping can put the bars back on screen.
  void scrollBy(double delta, {required bool atTop}) {
    if (delta <= 0) return;
    // At the very top there is nothing to scroll away from, so the chrome
    // stays: an overscroll bounce must not cost the reader the bars.
    if (atTop) {
      _reset();
      return;
    }
    if (locked) return;
    _reset();
    _down += delta;
    if (_down >= hideThreshold) {
      _down = 0;
      hide();
    }
  }

  /// A finger touched the feed. Nothing is earned yet; the clock starts on the
  /// first frame that travels in the reveal direction.
  void pointerDown() => _reset();

  /// The finger travelled [dy] pixels down the screen, which is the direction
  /// that pushes the feed back towards its top.
  ///
  /// The reveal is earned by the finger, not by the content: [dy] only ever
  /// comes from a pointer that is still on the screen, so the clock it starts
  /// dies the moment the finger lifts.
  void pointerMoved(double dy) {
    if (!hidden || locked) return;
    if (dy <= 0) {
      // The finger turned around, so the travel so far is a re-read, not a
      // request for the chrome.
      _reset();
      return;
    }
    _up += dy;
    if (_delay.value == 0 && !_delay.isAnimating) {
      _delay.forward(from: 0);
    }
    if (_up >= showThreshold) {
      if (_delay.value >= 1) {
        show();
      } else {
        _revealPending = true;
      }
    }
  }

  /// The finger left the screen, so any reveal it had not finished earning is
  /// dropped.
  void pointerUp() => _reset();

  void hide() {
    _leaving = true;
    _reset();
    if (_animation.value == 0) return;
    _lock.forward(from: 0);
    _animation.animateTo(0, duration: hideDuration, curve: Curves.easeInCubic);
  }

  void show() {
    _leaving = false;
    _reset();
    if (_animation.value == 1) return;
    _lock.forward(from: 0);
    _animation.animateTo(1, duration: showDuration, curve: Curves.easeOutCubic);
  }

  void _reset() {
    _down = 0;
    _up = 0;
    _revealPending = false;
    _stopDelay();
  }

  void _stopDelay() {
    if (_delay.isAnimating) _delay.stop();
    _delay.value = 0;
  }

  void _onShowDelayStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final showNow = _revealPending && _up >= showThreshold;
    _revealPending = false;
    if (showNow) show();
  }

  @override
  void dispose() {
    _animation.removeListener(notifyListeners);
    _delay.removeStatusListener(_onShowDelayStatus);
    _animation.dispose();
    _delay.dispose();
    _lock.dispose();
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

  static ScrollChromeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ScrollChromeScope>()?.notifier;

  /// Effective progress for the top toolbar; 1 outside a [ScrollChromeScope].
  static double topProgressOf(BuildContext context) =>
      _progressOf(context, true);

  /// Effective progress for the bottom navigation and the body inset.
  static double bottomProgressOf(BuildContext context) =>
      _progressOf(context, false);

  /// True while the chrome is sliding out, false when it is docked or arriving.
  static bool hidingOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ScrollChromeScope>()
          ?.notifier
          ?.hiding ??
      false;

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

/// Tells the glass surfaces inside a chrome bar that the bar is in motion.
///
/// Sampling the backdrop every frame while a bar slides is the expensive half
/// of the glass effect, and it is invisible during the slide, so a moving bar
/// paints its tint flat and only switches the blur back on once it is docked.
class GlassMotionScope extends InheritedWidget {
  const GlassMotionScope({
    super.key,
    required this.moving,
    required super.child,
  });

  final bool moving;

  static bool movingOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassMotionScope>()?.moving ??
      false;

  @override
  bool updateShouldNotify(GlassMotionScope oldWidget) =>
      oldWidget.moving != moving;
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
    // A bar that is leaving, or already gone, paints its tint flat: sampling
    // the backdrop while it slides is the expensive half of the glass effect
    // and nobody can see it. A bar that is arriving keeps the blur the whole
    // way in, because switching it on in the final frame popped the surface and
    // read as a jump right as it docked.
    final moving = ScrollChromeScope.hidingOf(context) || slide >= 1;
    return GlassMotionScope(
      moving: moving,
      child: FractionalTranslation(
        translation: Offset(0, top ? -slide : slide),
        // Hit testing follows the untranslated slot; [IgnorePointer] is what
        // actually stops taps once the surface starts to leave.
        transformHitTests: false,
        child: IgnorePointer(
          ignoring: slide > 0,
          // A fully hidden surface is off screen, so it stops painting too: no
          // backdrop sample and no layer work while the reader is reading.
          child: Opacity(opacity: slide >= 1 ? 0 : 1, child: child),
        ),
      ),
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

  @override
  State<ScrollChromeHost> createState() => _ScrollChromeHostState();
}

class _ScrollChromeHostState extends State<ScrollChromeHost> {
  /// A finger that wandered further than this was dragging the feed, not
  /// tapping it.
  static const double _tapSlop = 16;

  Offset? _downAt;
  bool _wandered = false;

  void _handleDown(PointerDownEvent event) {
    _downAt = event.position;
    _wandered = false;
    widget.controller.pointerDown();
  }

  void _handleMove(PointerMoveEvent event) {
    final down = _downAt;
    if (down != null && (event.position - down).distance > _tapSlop) {
      _wandered = true;
    }
    widget.controller.pointerMoved(event.delta.dy);
  }

  void _handleUp(PointerEvent event) {
    final down = _downAt;
    _downAt = null;
    widget.controller.pointerUp();
    // A tap, and only a tap, is the manual way back to a full bar. It is
    // detected here rather than with a [GestureDetector] because a gesture
    // recognizer on this level competes in the arena with every card and
    // button below it, and a raw pointer never does.
    final wandered = _wandered;
    _wandered = false;
    if (down != null &&
        !wandered &&
        (event.position - down).distance <= _tapSlop) {
      widget.controller.show();
    }
  }

  bool _onNotification(ScrollNotification notification) {
    if (!widget.enabled) return false;
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta;
      // A horizontal pager must not toggle the chrome of the vertical feed.
      if (delta == null ||
          delta == 0 ||
          notification.metrics.axis != Axis.vertical) {
        return false;
      }
      // Scroll frames only ever hide the chrome. Momentum, bouncing and
      // clamping all arrive here, and none of them may bring the bars back.
      widget.controller.scrollBy(
        delta,
        atTop: notification.metrics.extentBefore <= 0,
      );
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: Listener(
        // Raw pointers, not scroll deltas: this is what makes the reveal a
        // property of the finger instead of a property of the content.
        behavior: HitTestBehavior.translucent,
        onPointerDown: enabled ? _handleDown : null,
        onPointerMove: enabled ? _handleMove : null,
        onPointerUp: enabled ? _handleUp : null,
        onPointerCancel: enabled ? _handleUp : null,
        child: widget.child,
      ),
    );
  }
}
