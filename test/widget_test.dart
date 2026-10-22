import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:rootgist/app_shell.dart';
import 'package:rootgist/data/models.dart';
import 'package:rootgist/data/repository.dart';
import 'package:rootgist/debug/widget_gallery.dart';
import 'package:rootgist/design/typography.dart';
import 'package:rootgist/features/explore/explore_screen.dart';
import 'package:rootgist/features/home/home_screen.dart';
import 'package:rootgist/features/reader/reader_screen.dart';
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

// 화면 이동 뒤 새 화면의 fixture 읽기도 같은 이유로 실제 async 영역에서 프레임을 그린다.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pump();
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
    await settle(tester);
    expect(find.text('arXiv · 0000.00002'), findsOneWidget);
  });

  test('8.3 LaTeX 표시 변환과 근거 없는 핵심 내용 제외', () {
    expect(latexDisplay(r'uses 30\% less, a\_b \& c'), 'uses 30% less, a_b & c');
    expect(latexDisplay(r'3 \times 4 and 10\times faster'), '3×4 and 10× faster');
    expect(latexDisplay(r'a~b\,c'), 'a b c');

    final p = PaperDetail.fromJson({
      'paper_id': 'x', 'title_en': 'T', 'authors': ['A'], 'published_at': '2026-10-18',
      'hf_url': '', 'arxiv_url': '', 'ai_status': 'ready',
      'key_points': [
        {'claim_ko': '근거 있음', 'evidence_sentence_ids': ['A03']},
        {'claim_ko': '근거 없음', 'evidence_sentence_ids': []},
      ],
    });
    expect(p.keyPoints.map((k) => k.claim), ['근거 있음']);
    expect(p.authorLine, 'A'); // 단독 저자는 「외」 없음
    expect(sentenceNumber('A03'), 3);
  });

  testWidgets('S02: 근거 링크 → C01 시트, 게시 조직 행(G8)', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);

    router.push('/paper/0000.00001');
    await settle(tester);
    expect(find.text('Efficient Scaling of Inference-Time Compute'), findsOneWidget);
    expect(find.text('원문 근거 · 초록 4번째 문장'), findsOneWidget);
    expect(find.text('게시 조직'), findsNothing);

    await tester.tap(find.text('원문 근거 · 초록 4번째 문장'));
    await tester.pumpAndSettle();
    expect(find.text('핵심 내용 3의 근거'), findsOneWidget);
    expect(find.text('On the example benchmark, the method uses 30% less compute at matched accuracy.'), findsOneWidget);

    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('핵심 내용 3의 근거'), findsNothing);

    router.push('/paper/0000.00004');
    await settle(tester);
    expect(find.text('Example Lab'), findsOneWidget);
  });

  test('S03: 용어 하이라이트는 highlight=true만, 용어당 처음 1회', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final p = await repository.getPaper('0000.00001');
    final h = firstHighlights(p);
    expect(h.keys, unorderedEquals(['A01', 'A03'])); // Benchmark(highlight=false)는 없음
    expect(h['A01']!.single.$2.term, 'inference-time compute');
    expect(h['A01']!.single.$1, 'For large language models, '.length);
  });

  testWidgets('S03: 모드 전환, 용어 탭 → C02', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);

    router.push('/paper/0000.00001/reader?s=A03');
    await settle(tester);
    final ko = keepAll('본 연구는 입력 복잡도에 따라 추론 연산을 동적으로 배분하는 방법을 제안한다.');
    expect(find.text(ko), findsOneWidget);
    expect(find.text('Benchmark'), findsNothing);

    await tester.tap(find.bySemanticsLabel('용어 설명: compute budget'));
    await tester.pumpAndSettle();
    expect(find.text('이 논문에서의 뜻'), findsOneWidget);
    expect(find.text(keepAll('학습이나 추론에 쓸 수 있도록 미리 정해 둔 계산량의 한도.')), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('원문'));
    await tester.pumpAndSettle();
    expect(find.text(ko), findsNothing);
    expect(find.bySemanticsLabel('용어 설명: inference-time compute'), findsOneWidget);
  });

  test('S04: 오늘 제외, 월 묶음, 지연 시각은 KST', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final today = await repository.todayKey();
    final days = [for (final d in await repository.listDigests()) if (d.dateKey != today) d];
    final months = groupByMonth(days);
    expect(months.map((m) => m.$1), ['2026년 10월', '2026년 9월']);
    expect(months.first.$2.map((d) => d.dateKey), ['2026-10-18', '2026-10-17', '2026-10-16']);
    expect(kstTime(DateTime.parse('2026-10-17T00:00:00Z')), '09:00');
  });

  testWidgets('S04: 정상 날짜 → 그날의 S01, 지연·없음은 탭 안 됨', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);

    await tester.tap(find.text('탐색'));
    await settle(tester);
    expect(find.text('수집이 늦어지고 있어요 · 마지막 정상 수집 09:00'), findsOneWidget);
    expect(find.text('1편 · 기타'), findsOneWidget); // 단독이면 「외」 없음
    expect(find.text('10월 19일 월요일'), findsNothing); // 오늘 제외

    await tester.tap(find.text('10월 18일 일요일'));
    await settle(tester);
    expect(find.bySemanticsLabel('뒤로'), findsOneWidget);
    expect(find.textContaining('10월 18일 일요일', findRichText: true), findsWidgets);

    await tester.tap(find.bySemanticsLabel('뒤로'));
    await tester.pumpAndSettle();
    expect(find.text('지난 날짜의 연구를 다시 볼 수 있어요'), findsOneWidget);
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
