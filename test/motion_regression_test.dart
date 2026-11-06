import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rootgist/data/repository.dart';
import 'package:rootgist/design/theme.dart';
import 'package:rootgist/design/widgets/rg_buttons.dart';
import 'package:rootgist/design/widgets/rg_bookmark_motion.dart';
import 'package:rootgist/design/widgets/rg_pressable.dart';
import 'package:rootgist/features/paper/paper_screen.dart';

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  bool reduced = false,
}) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      MaterialApp(
        theme: rgTheme,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: child,
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => bookmarks.value = {});

  testWidgets('활성 북마크를 iOS 접근성에도 활성 컨트롤로 전달한다', (tester) async {
    await mount(
      tester,
      Scaffold(body: RgBookmarkButton(saved: false, onTap: () {})),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('북마크에 저장')),
      isSemantics(isEnabled: true, hasEnabledState: true),
    );
    await mount(
      tester,
      const Scaffold(body: RgBookmarkButton(saved: false, onTap: null)),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('북마크에 저장')),
      isSemantics(isEnabled: false, hasEnabledState: true),
    );
  });

  testWidgets('북마크 반응 중 동작 줄이기를 켜면 크기와 ticker가 즉시 안정된다', (tester) async {
    var saved = false;
    var reduced = false;
    late StateSetter update;
    await mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: Scaffold(
              body: RgBookmarkButton(
                saved: saved,
                onTap: () => setState(() => saved = !saved),
              ),
            ),
          );
        },
      ),
    );
    final pulse = find.descendant(
      of: find.byType(RgBookmarkButton),
      matching: find.byType(ScaleTransition),
    );
    expect(tester.widget<ScaleTransition>(pulse).scale.value, 1);
    await tester.tap(find.bySemanticsLabel('북마크에 저장'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.widget<ScaleTransition>(pulse).scale.value, isNot(1));
    update(() => reduced = true);
    await tester.pump();
    expect(tester.widget<ScaleTransition>(pulse).scale.value, 1);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('논문 dock 저장·해제는 상태를 바꾸고 공통 북마크 모션으로 피드백한다', (tester) async {
    bookmarks.value = {};
    await mount(tester, const PaperScreen(paperId: '0000.00001'));
    final bookmark = find.bySemanticsLabel('북마크에 저장');
    expect(bookmark, findsOneWidget);
    await tester.tap(bookmark);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(bookmarks.value.containsKey('0000.00001'), isTrue);
    expect(
      find.descendant(
        of: find.byType(RgBookmarkMotion),
        matching: find.byWidgetPredicate(
          (w) => w is ScaleTransition && w.scale.value != 1,
        ),
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    // 연속 탭으로 상태가 밀리거나 애니메이션이 남지 않는다.
    await tester.tap(find.bySemanticsLabel('저장됨, 북마크 해제'));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.bySemanticsLabel('북마크에 저장'));
    await tester.pumpAndSettle();
    expect(bookmarks.value.containsKey('0000.00001'), isTrue);
    expect(
      tester
          .widget<ScaleTransition>(
            find.descendant(
              of: find.byType(RgBookmarkMotion),
              matching: find.byType(ScaleTransition),
            ),
          )
          .scale
          .value,
      1,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('비활성 누름 영역은 접근성 탭 동작도 노출하지 않는다', (tester) async {
    await mount(
      tester,
      Scaffold(
        body: Semantics(
          label: '사용할 수 없는 동작',
          child: RgPressable(
            onTap: null,
            child: SizedBox(width: 44, height: 44),
          ),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('사용할 수 없는 동작')),
      isSemantics(hasTapAction: false),
    );
  });

  testWidgets('행을 세로로 스크롤하면 눌림을 취소하고 화면을 열지 않는다', (tester) async {
    var opened = 0;
    await mount(
      tester,
      Scaffold(
        body: ListView(
          children: [
            RgPressable(
              row: true,
              onTap: () => opened++,
              child: const SizedBox(height: 400),
            ),
            const SizedBox(height: 1600),
          ],
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(200, 250));
    await tester.pump(const Duration(milliseconds: 160));
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      0.98,
    );
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      greaterThan(0),
    );
  });

  testWidgets('누르는 중 동작 줄이기를 켜면 행 크기도 즉시 복귀한다', (tester) async {
    var reduced = false;
    late StateSetter update;
    await mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: Scaffold(
              body: Center(
                child: RgPressable(
                  row: true,
                  onTap: () {},
                  child: const SizedBox(width: 200, height: 100),
                ),
              ),
            ),
          );
        },
      ),
    );
    final pressable = find.byType(RgPressable);
    final gesture = await tester.startGesture(tester.getCenter(pressable));
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pump(const Duration(milliseconds: 120));
    double paintedScale() => tester
        .widget<Transform>(
          find
              .descendant(of: pressable, matching: find.byType(Transform))
              .first,
        )
        .transform
        .storage[0];
    expect(paintedScale(), closeTo(0.98, 0.001));
    update(() => reduced = true);
    await tester.pump();
    expect(paintedScale(), 1);
    await gesture.cancel();
    await tester.pumpAndSettle();
  });
}
