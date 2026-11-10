import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rootgist/data/guide.dart';
import 'package:rootgist/data/repository.dart';
import 'package:rootgist/design/widgets/rg_states.dart';
import 'package:rootgist/features/explore/explore_screen.dart';

Widget _skeleton({required bool reduced}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: const RgSkeleton(child: SizedBox(width: 100, height: 20)),
  ),
);

double _skeletonOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find.descendant(
        of: find.byType(RgSkeleton),
        matching: find.byType(FadeTransition),
      ),
    )
    .opacity
    .value;

Future<PageController> _explore(
  WidgetTester tester, {
  required bool reduced,
}) async {
  fixtureMode.value = FixtureMode.loading;
  exploreJump.value = null;
  exploreTab.value = 0;
  newsTab.value = 0;
  toolsTab.value = 0;
  tipsSeen.value = {tipNews, tipReader};
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: const Scaffold(body: ExploreScreen()),
      ),
    ),
  );
  await tester.pump();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    exploreJump.value = null;
    fixtureMode.value = FixtureMode.normal;
  });
  return tester.widget<PageView>(find.byType(PageView)).controller!;
}

void main() {
  testWidgets(
    'reduced-motion loading stays fully visible without a running ticker',
    (tester) async {
      await tester.pumpWidget(_skeleton(reduced: true));
      await tester.pump(const Duration(milliseconds: 150));
      expect(_skeletonOpacity(tester), 1);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_skeletonOpacity(tester), 1);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('loading stops and resumes when the motion preference changes', (
    tester,
  ) async {
    await tester.pumpWidget(_skeleton(reduced: false));
    await tester.pump(const Duration(milliseconds: 150));
    expect(_skeletonOpacity(tester), lessThan(1));
    await tester.pumpWidget(_skeleton(reduced: true));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_skeletonOpacity(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(_skeleton(reduced: false));
    await tester.pump(const Duration(milliseconds: 150));
    expect(_skeletonOpacity(tester), lessThan(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'reduced-motion explore swipe requests reach the next page immediately',
    (tester) async {
      final pages = await _explore(tester, reduced: true);
      exploreJump.value = const ExploreJump(1, animate: true);
      await tester.pump();
      expect(pages.page, 1);
      expect(exploreTab.value, 1);
    },
  );

  testWidgets(
    'reduced-motion primary tab taps jump without a zero-duration scroll',
    (tester) async {
      final pages = await _explore(tester, reduced: true);
      await tester.tap(find.text('도구'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(pages.page, 2);
      expect(exploreTab.value, 2);
    },
  );

  testWidgets(
    'explore swipe requests keep their page animation when motion is allowed',
    (tester) async {
      final pages = await _explore(tester, reduced: false);
      exploreJump.value = const ExploreJump(1, animate: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(pages.page, greaterThan(0));
      expect(pages.page, lessThan(1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(pages.page, 1);
    },
  );
}
