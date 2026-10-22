import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:rootgist/debug/widget_gallery.dart';
import 'package:rootgist/main.dart';

void main() {
  testWidgets('탭 4개가 뜨고 전환된다', (tester) async {
    await tester.pumpWidget(const RootgistApp());
    await tester.pumpAndSettle();

    expect(find.text('오늘의 연구'), findsOneWidget);
    for (final label in ['홈', '탐색', '보관함', '설정']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('보관함'));
    await tester.pumpAndSettle();
    expect(find.text('보관함'), findsNWidgets(2)); // 탭 라벨 + 화면 제목
  });

  test('fixture JSON이 에셋으로 읽힌다', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final list = jsonDecode(await rootBundle.loadString('fixtures/digests.json'));
    expect(list['fixture_today'], '2026-10-19');
    final paper = jsonDecode(await rootBundle.loadString('fixtures/papers/0000.00001.json'));
    expect(paper['paper_id'], '0000.00001');
  });

  testWidgets('위젯 갤러리: 세그먼트·북마크·시트가 동작한다', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: WidgetGallery()));

    await tester.tap(find.text('원문'));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.text('원문')), isSemantics(isSelected: true));

    expect(find.bySemanticsLabel('저장됨, 북마크 해제'), findsOneWidget); // 카드 안 i==1 행
    await tester.tap(find.bySemanticsLabel('북마크에 저장').first);
    await tester.pump();
    expect(find.bySemanticsLabel('저장됨, 북마크 해제'), findsNWidgets(4));

    await tester.tap(find.text('시트 열기'));
    await tester.pumpAndSettle();
    expect(find.text('inference-time compute'), findsOneWidget);
    await tester.tap(find.text('닫기').last);
    await tester.pumpAndSettle();
    expect(find.text('inference-time compute'), findsNothing);
  });
}
