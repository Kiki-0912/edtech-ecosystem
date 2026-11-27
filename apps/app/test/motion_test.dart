import 'dart:ui' show PointerDeviceKind;

import 'package:edtech_app/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
      theme: lightTheme,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  group('CountUpText', () {
    testWidgets('counts up to the value and keeps prefix, suffix and commas',
        (tester) async {
      await tester.pumpWidget(_host(const CountUpText('92%')));
      expect(find.text('92%'), findsNothing, reason: 'starts at 0');
      await tester.pumpAndSettle();
      expect(find.text('92%'), findsOneWidget);

      await tester.pumpWidget(_host(const CountUpText('1,240 students')));
      await tester.pumpAndSettle();
      expect(find.text('1,240 students'), findsOneWidget);

      await tester.pumpWidget(_host(const CountUpText('3.5 h')));
      await tester.pumpAndSettle();
      expect(find.text('3.5 h'), findsOneWidget);
    });

    testWidgets('text without a number is shown as is', (tester) async {
      await tester.pumpWidget(_host(const CountUpText('Open')));
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('reduced motion shows the final value immediately',
        (tester) async {
      await tester
          .pumpWidget(_host(const CountUpText('92%'), reduceMotion: true));
      expect(find.text('92%'), findsOneWidget);
    });
  });

  group('FadeSlideIn', () {
    testWidgets('fades in once settled; staggered items finish later',
        (tester) async {
      await tester.pumpWidget(_host(const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeSlideIn(child: Text('first', key: Key('first'))),
          FadeSlideIn(
              delay: Duration(milliseconds: 80),
              child: Text('second', key: Key('second'))),
        ],
      )));
      double opacity(String key) => tester
          .widget<Opacity>(find
              .ancestor(
                  of: find.byKey(Key(key)), matching: find.byType(Opacity))
              .first)
          .opacity;
      await tester.pump(const Duration(milliseconds: 140));
      expect(opacity('first'), greaterThan(opacity('second')));
      await tester.pumpAndSettle();
      expect(opacity('first'), 1);
      expect(opacity('second'), 1);
    });

    testWidgets('reduced motion renders fully visible on the first frame',
        (tester) async {
      await tester.pumpWidget(_host(
        const FadeSlideIn(child: Text('now', key: Key('now'))),
        reduceMotion: true,
      ));
      final opacity = tester.widget<Opacity>(find
          .ancestor(
              of: find.byKey(const Key('now')), matching: find.byType(Opacity))
          .first);
      expect(opacity.opacity, 1);
    });
  });

  group('Pressable', () {
    testWidgets('scales down while pressed and does not swallow taps',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(Pressable(
        child: FilledButton(
            key: const Key('btn'),
            onPressed: () => taps++,
            child: const Text('Go')),
      )));
      final gesture = await tester
          .startGesture(tester.getCenter(find.byKey(const Key('btn'))));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
          lessThan(1));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    });
  });

  group('Skeleton', () {
    testWidgets('pulses a few times then rests so the tree can settle',
        (tester) async {
      await tester.pumpWidget(_host(const Skeleton(width: 80, height: 20)));
      await tester.pumpAndSettle(); // would time out if it pulsed forever
      expect(find.byType(Skeleton), findsOneWidget);
    });
  });

  group('success moments', () {
    testWidgets('check and burst play once and settle', (tester) async {
      await tester.pumpWidget(_host(const Stack(
        alignment: Alignment.center,
        children: [SuccessBurst(), AnimatedCheck(size: 32)],
      )));
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedCheck), findsOneWidget);
      expect(find.byType(SuccessBurst), findsOneWidget);
    });
  });

  group('SwitchFade', () {
    testWidgets('keeps the child mounted when the token changes',
        (tester) async {
      Widget build(int token) =>
          _host(SwitchFade(token: token, child: const _Counter()));
      await tester.pumpWidget(build(0));
      await tester.tap(find.byType(_Counter));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);

      await tester.pumpWidget(build(1));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget, reason: 'state survives');
    });
  });

  group('HoverLift', () {
    testWidgets('lifts on hover and settles back', (tester) async {
      await tester.pumpWidget(_host(const HoverLift(
          child: SizedBox(key: Key('lift-child'), width: 100, height: 40))));
      final start = tester.getTopLeft(find.byKey(const Key('lift-child'))).dy;

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byKey(const Key('lift-child'))));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(const Key('lift-child'))).dy,
          lessThan(start));

      await mouse.moveTo(const Offset(700, 500));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(const Key('lift-child'))).dy, start);
    });
  });

  group('LineIllustration', () {
    testWidgets('draws once and settles, for every kind', (tester) async {
      for (final kind in IllustrationKind.values) {
        await tester.pumpWidget(_host(LineIllustration(kind: kind)));
        await tester.pumpAndSettle();
        expect(find.byType(LineIllustration), findsOneWidget);
      }
    });

    testWidgets('empty and error states use them', (tester) async {
      await tester.pumpWidget(_host(const EmptyState(
          icon: Icons.inbox,
          illustration: IllustrationKind.nothing,
          title: 'Nothing here')));
      await tester.pumpAndSettle();
      expect(find.byType(LineIllustration), findsOneWidget);

      await tester.pumpWidget(_host(const ErrorState(message: 'boom')));
      await tester.pumpAndSettle();
      expect(find.byType(LineIllustration), findsOneWidget);
    });
  });

  group('AppMotion', () {
    test('delays are capped so long lists do not wait', () {
      expect(AppMotion.delayFor(0), Duration.zero);
      expect(AppMotion.delayFor(3), AppMotion.stagger * 3);
      expect(AppMotion.delayFor(50), AppMotion.stagger * AppMotion.maxStagger);
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _n = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => setState(() => _n++),
        child: Text('$_n'),
      );
}
