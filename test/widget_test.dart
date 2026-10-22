import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:rootgist/app_shell.dart';
import 'package:rootgist/data/repository.dart';
import 'package:rootgist/debug/widget_gallery.dart';
import 'package:rootgist/design/typography.dart';
import 'package:rootgist/features/home/home_screen.dart';
import 'package:rootgist/main.dart';

// 에셋 읽기는 실제 I/O라 fake async 안에서 시작하면 끝나지 않고, rootBundle이 그 미완료 Future를 캐시해
// 다음 테스트까지 막는다. 첫 프레임(initState의 fixture 읽기)을 실제 async 영역에서 띄운다.
Future<void> pumpApp(WidgetTester tester) async {
  router.go('/home'); // 전역 라우터라 이전 테스트의 탭 위치가 남는다
  await tester.runAsync(() async {
    await tester.pumpWidget(const RootgistApp());
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('탭 4개가 뜨고 전환된다', (tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();

    expect(find.text('ROOTGIST'), findsOneWidget);
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

  test('S01: 주요 연구 선정·필터·편수 규칙', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final papers = (await repository.today())!.papers;

    final all = HomeView(papers, null);
    expect(all.total, 6);
    expect(all.featured!.id, '0000.00001'); // 1위가 pending → 2위(G9)
    expect(all.list.length, 5); // 추천 논문은 목록에서 빠짐
    expect(all.list.first.title, 'Benchmarking Long-Context Retrieval'); // pending은 영문 제목(G14)
    expect(all.chips, ['llm', 'agent', 'multimodal', 'optimization']);

    final opt = HomeView(papers, 'optimization');
    expect(opt.total, 6); // 헤드라인 편수는 전체 기준
    expect(opt.featured, isNull); // 핵심 내용 0개
    expect(opt.list.map((p) => p.id), ['0000.00005']);

    expect(koreanDate(DateTime(2026, 10, 19)), '10월 19일 월요일');
  });

  testWidgets('S01: 행 탭은 S02로, 북마크는 이동 없이 토글', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);

    expect(find.text('5편'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('북마크에 저장').first);
    await tester.pump();
    expect(bookmarks.value, {'0000.00001'});

    await tester.tap(find.text(keepAll('소수 예시 기반 영상 분할의 일반화 성능 분석')));
    await tester.pumpAndSettle();
    expect(find.textContaining('0000.00002'), findsOneWidget);
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
