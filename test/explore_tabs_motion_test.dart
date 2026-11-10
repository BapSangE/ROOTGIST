import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rootgist/design/theme.dart';
import 'package:rootgist/features/explore/date_groups.dart';

const _paint = ValueKey('tabs-paint');

Future<void> _mount(
  WidgetTester tester, {
  bool reduceMotion = false,
  double scale = 1,
  double width = 390,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: rgTheme,
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: reduceMotion,
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: RepaintBoundary(key: _paint, child: const _Tabs()),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Tabs extends StatefulWidget {
  const _Tabs();
  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  int selected = 0;
  @override
  Widget build(BuildContext context) => ExploreSectionTabs(
    labels: const ['발표', '업데이트', '커뮤니티'],
    selected: selected,
    onTap: (i) => setState(() => selected = i),
  );
}

// Inspect the painted stroke rather than a particular animation widget:
// fading separate tab borders must not pass as one moving underline.
Future<List<(int, int)>> _strokes(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_paint),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final runs = <(int, int)>[];
    int? start;
    final y = image.height - 3; // indicator sits immediately above the divider
    for (var x = 0; x <= image.width; x++) {
      final at = (y * image.width + x) * 4;
      final ink =
          x < image.width &&
          data.getUint8(at) < 60 &&
          data.getUint8(at + 1) < 60 &&
          data.getUint8(at + 2) < 60 &&
          data.getUint8(at + 3) > 240;
      if (ink) {
        start ??= x;
      } else if (start != null) {
        runs.add((start, x));
        start = null;
      }
    }
    image.dispose();
    return runs;
  }))!;
}

double _center((int, int) run) => (run.$1 + run.$2) / 2;
double _labelCenter(WidgetTester tester, String label) =>
    tester.getCenter(find.text(label)).dx -
    tester.getTopLeft(find.byKey(_paint)).dx;

void main() {
  testWidgets('보조 탭 밑줄은 한 선으로 선택한 탭까지 이동한다', (tester) async {
    await _mount(tester);
    final initial = (await _strokes(tester)).single;
    await tester.tap(find.text('업데이트'));
    await tester.pump();
    await tester.pump(); // post-layout tab measurement
    await tester.pump(const Duration(milliseconds: 60));
    final midway = await _strokes(tester);
    expect(midway, hasLength(1), reason: '중간 프레임에도 두 선이 따로 페이드하지 않아야 한다.');
    expect(_center(midway.single), greaterThan(_center(initial) + 1));
    expect(_center(midway.single), lessThan(_labelCenter(tester, '업데이트') - 1));
    await tester.pumpAndSettle();
    expect(
      _center((await _strokes(tester)).single),
      closeTo(_labelCenter(tester, '업데이트'), 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('연속 탭 선택은 현재 밑줄 위치에서 이어지고 최종 선택에 멈춘다', (tester) async {
    await _mount(tester);
    await tester.tap(find.text('업데이트'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final before = _center((await _strokes(tester)).single);
    await tester.tap(find.text('커뮤니티'));
    await tester.pump();
    await tester.pump();
    expect(_center((await _strokes(tester)).single), closeTo(before, 1));
    await tester.pump(const Duration(milliseconds: 50));
    final moving = _center((await _strokes(tester)).single);
    expect(moving, greaterThan(before));
    await tester.tap(find.text('발표'));
    await tester.pump();
    await tester.pump();
    expect(_center((await _strokes(tester)).single), closeTo(moving, 1));
    await tester.pumpAndSettle();
    expect(
      _center((await _strokes(tester)).single),
      closeTo(_labelCenter(tester, '발표'), 1),
    );
    expect(
      tester
          .getSemantics(find.text('발표'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('동작 줄이기는 이동 없이 최종 밑줄을 표시하고 큰 글자·가로 스크롤에도 맞는다', (tester) async {
    await _mount(tester, reduceMotion: true, scale: 2, width: 240);
    await tester.ensureVisible(find.text('커뮤니티'));
    await tester.tap(find.text('커뮤니티'));
    await tester.pump();
    await tester.pump();
    final stroke = (await _strokes(tester)).single;
    expect(_center(stroke), closeTo(_labelCenter(tester, '커뮤니티'), 1));
    expect(stroke.$1, greaterThanOrEqualTo(0));
    expect(stroke.$2, lessThanOrEqualTo(240));
    expect(tester.takeException(), isNull);
  });
}
