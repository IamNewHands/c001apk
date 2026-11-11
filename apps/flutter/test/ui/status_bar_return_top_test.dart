import 'package:c001apk_flutter/components/status_bar_return_top.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(StatusBarReturnTop.clear);
  tearDown(StatusBarReturnTop.clear);

  Finder strip() => find.byKey(const ValueKey('status-bar-return-top'));

  /// Mirrors the root layout in `main.dart`: the app sits under a transparent
  /// strip that only exists when the platform reserves a status bar inset.
  Widget app({double topInset = 24, Widget? body}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(400, 800),
            padding: EdgeInsets.only(top: topInset),
            viewPadding: EdgeInsets.only(top: topInset),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: body ?? const ColoredBox(color: Colors.white),
              ),
              // `enabled` because tests do not run on iOS.
              const StatusBarTapDetector(enabled: true),
            ],
          ),
        ),
      );

  testWidgets('a tap on the strip runs the bound handler', (tester) async {
    await tester.pumpWidget(app());
    var taps = 0;
    StatusBarReturnTop.bind('page', () => taps++);

    await tester.tap(strip());
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('a tap with nothing bound stays silent', (tester) async {
    await tester.pumpWidget(app());

    await tester.tap(strip());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('no strip is laid out without a top inset', (tester) async {
    await tester.pumpWidget(app(topInset: 0));

    expect(strip(), findsNothing);
  });

  testWidgets('the newest active binding wins', (tester) async {
    await tester.pumpWidget(app());
    final order = <String>[];
    StatusBarReturnTop.bind('older', () => order.add('older'));
    StatusBarReturnTop.bind('newer', () => order.add('newer'));

    await tester.tap(strip());
    await tester.pump();

    expect(order, ['newer']);
  });

  testWidgets('an inactive binding is skipped', (tester) async {
    await tester.pumpWidget(app());
    final order = <String>[];
    StatusBarReturnTop.bind('visible', () => order.add('visible'));
    StatusBarReturnTop.bind(
      'covered',
      () => order.add('covered'),
      isActive: () => false,
    );

    await tester.tap(strip());
    await tester.pump();

    expect(order, ['visible']);
  });

  testWidgets('unbinding stops delivery', (tester) async {
    await tester.pumpWidget(app());
    var taps = 0;
    StatusBarReturnTop.bind('page', () => taps++);
    StatusBarReturnTop.unbind('page');

    await tester.tap(strip());
    await tester.pump();

    expect(taps, 0);
  });

  testWidgets('the mixin binds on mount and unbinds on dispose',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      app(body: _Host(() => taps++)),
    );

    await tester.tap(strip());
    await tester.pump();
    expect(taps, 1);

    // Dropping the host page must drop its registration too.
    await tester.pumpWidget(app());
    await tester.tap(strip());
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('iOS status bar tap via WidgetsBindingObserver triggers dispatch',
      (tester) async {
    StatusBarReturnTop.install();
    var taps = 0;
    StatusBarReturnTop.bind('page', () => taps++);

    final ByteData? message = const StandardMethodCodec()
        .encodeMethodCall(const MethodCall('handleScrollToTop'));
    await tester.binding.defaultBinaryMessenger
        .handlePlatformMessage('flutter/statusbar', message, (_) {});
    await tester.pump();

    expect(taps, 1);
  });
}

class _Host extends StatefulWidget {
  const _Host(this.onTap);

  final VoidCallback onTap;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with StatusBarReturnTopBinding<_Host> {
  @override
  void onStatusBarReturnTop() => widget.onTap();

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.white);
}
