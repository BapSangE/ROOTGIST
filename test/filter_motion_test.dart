import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rootgist/design/widgets/rg_row_head.dart';

Widget _filters(
  ValueNotifier<int> selected, {
  required bool reduced,
  bool resize = false,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Scaffold(
      body: SingleChildScrollView(
        child: ValueListenableBuilder<int>(
          valueListenable: selected,
          builder: (context, value, _) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (name, height) in [('short', 200.0), ('long', 6000.0)])
                Expanded(
                  child: RgFilterSwitch(
                    key: ValueKey('$name-filter'),
                    switchKey: value,
                    child: SizedBox(
                      height: height + (resize && value == 1 ? 100 : 0),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          key: ValueKey('$name-$value'),
                          width: 20,
                          height: 20,
                          child: const ColoredBox(color: Colors.black),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  ),
);

double _markerY(WidgetTester tester, String name, int value) =>
    tester.getTopLeft(find.byKey(ValueKey('$name-$value'))).dy;

void main() {
  testWidgets(
    'filter entry travels at most 8pt regardless of the list height',
    (tester) async {
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      await tester.pumpWidget(_filters(selected, reduced: false));
      final shortOrigin = _markerY(tester, 'short', 0);
      final longOrigin = _markerY(tester, 'long', 0);
      selected.value = 1;
      await tester.pump();
      for (final step in [16, 64]) {
        await tester.pump(Duration(milliseconds: step));
        final shortTravel = _markerY(tester, 'short', 1) - shortOrigin;
        final longTravel = _markerY(tester, 'long', 1) - longOrigin;
        expect(shortTravel, greaterThan(0));
        expect(shortTravel, lessThanOrEqualTo(8));
        expect(longTravel, lessThanOrEqualTo(8));
        expect(longTravel, closeTo(shortTravel, 0.01));
      }
      await tester.pump(const Duration(milliseconds: 200));
      expect(_markerY(tester, 'short', 1), closeTo(shortOrigin, 0.01));
      expect(_markerY(tester, 'long', 1), closeTo(longOrigin, 0.01));
    },
  );

  testWidgets(
    'reduced-motion filters appear at their final paint position immediately',
    (tester) async {
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      await tester.pumpWidget(_filters(selected, reduced: true));
      final shortOrigin = _markerY(tester, 'short', 0);
      final longOrigin = _markerY(tester, 'long', 0);
      selected.value = 1;
      await tester.pump();
      expect(_markerY(tester, 'short', 1), closeTo(shortOrigin, 0.01));
      expect(_markerY(tester, 'long', 1), closeTo(longOrigin, 0.01));
      await tester.pump(const Duration(milliseconds: 80));
      expect(_markerY(tester, 'short', 1), closeTo(shortOrigin, 0.01));
      expect(_markerY(tester, 'long', 1), closeTo(longOrigin, 0.01));
    },
  );

  testWidgets(
    'reduced-motion filters apply a new list height in the first frame',
    (tester) async {
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      await tester.pumpWidget(_filters(selected, reduced: true, resize: true));
      expect(
        tester.getSize(find.byKey(const ValueKey('short-filter'))).height,
        200,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('long-filter'))).height,
        6000,
      );
      selected.value = 1;
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const ValueKey('short-filter'))).height,
        300,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('long-filter'))).height,
        6100,
      );
    },
  );

  testWidgets('changing motion preferences preserves expanded content state', (
    tester,
  ) async {
    final reduced = ValueNotifier(false);
    addTearDown(reduced.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: reduced,
          builder: (context, value, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: value),
            child: const Scaffold(
              body: RgFilterSwitch(switchKey: 'same', child: _ExpansionProbe()),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('접힘'));
    await tester.pumpAndSettle();
    expect(find.text('열림'), findsOneWidget);
    reduced.value = true;
    await tester.pumpAndSettle();
    expect(find.text('열림'), findsOneWidget);
    reduced.value = false;
    await tester.pumpAndSettle();
    expect(find.text('열림'), findsOneWidget);
  });
}

class _ExpansionProbe extends StatefulWidget {
  const _ExpansionProbe();
  @override
  State<_ExpansionProbe> createState() => _ExpansionProbeState();
}

class _ExpansionProbeState extends State<_ExpansionProbe> {
  bool open = false;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => open = !open),
    child: Text(open ? '열림' : '접힘'),
  );
}
