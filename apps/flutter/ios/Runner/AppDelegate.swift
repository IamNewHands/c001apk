import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// Channel the status bar tap is forwarded on. Mirrors
  /// `StatusBarReturnTop.channel` on the Dart side.
  private static let statusBarChannelName = "app.awavenue.c001apk/status_bar"

  private var statusBarChannel: FlutterMethodChannel?

  /// A scroll view that exists only to claim the status bar tap. iOS routes that
  /// gesture to the app's scroll views instead of delivering a touch, so the
  /// Flutter view never sees it; this one hands it back over the channel.
  private var statusBarTapCatcher: UIScrollView?

  /// Last forwarded tap, so the two delegate callbacks cannot both report one
  /// tap when iOS runs them back to back.
  private var lastStatusBarTap = Date.distantPast

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    application.applicationSupportsShakeToEdit = false
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    installStatusBarTapCatcher()
    observeActivation()
    return launched
  }

  /// Retried when the app becomes active, because the window may not exist yet
  /// while `didFinishLaunching` runs; the guard makes the repeat call free.
  private func observeActivation() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
  }

  @objc private func handleDidBecomeActive() {
    installStatusBarTapCatcher()
  }

  private func installStatusBarTapCatcher() {
    guard statusBarTapCatcher == nil,
          let controller = window?.rootViewController as? FlutterViewController
    else { return }

    statusBarChannel = FlutterMethodChannel(
      name: AppDelegate.statusBarChannelName,
      binaryMessenger: controller.binaryMessenger
    )

    let catcher = UIScrollView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    // iOS only offers a status bar tap to a scroll view whose content is taller
    // than its frame and whose scrolling is left on, so both stay in place; the
    // delegate declines the scroll below, so the catcher never actually moves.
    catcher.contentSize = CGSize(width: 1, height: 2)
    catcher.scrollsToTop = true
    catcher.bounces = false
    catcher.showsVerticalScrollIndicator = false
    catcher.showsHorizontalScrollIndicator = false
    catcher.backgroundColor = .clear
    catcher.delegate = self
    controller.view.addSubview(catcher)
    statusBarTapCatcher = catcher
  }

  private func forwardStatusBarTap() {
    let now = Date()
    guard now.timeIntervalSince(lastStatusBarTap) > 0.2 else { return }
    lastStatusBarTap = now
    statusBarChannel?.invokeMethod("returnToTop", arguments: nil)
  }
}

extension AppDelegate: UIScrollViewDelegate {
  /// iOS asks before animating a status bar tap. Returning false keeps the
  /// catcher still; the Flutter page scrolls itself instead.
  func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
    guard scrollView === statusBarTapCatcher else { return true }
    forwardStatusBarTap()
    return false
  }

  func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
    guard scrollView === statusBarTapCatcher else { return }
    forwardStatusBarTap()
  }
}
