import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:rootgist/app_shell.dart';
import 'package:rootgist/data/guide.dart';
import 'package:rootgist/data/models.dart';
import 'package:rootgist/data/repository.dart';
import 'package:rootgist/data/settings.dart';
import 'package:rootgist/data/supabase_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rootgist/data/storage.dart';
import 'package:rootgist/data/unread.dart';
import 'package:rootgist/design/widgets/rg_new_dot.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rootgist/features/settings/ai_notice_sheet.dart';
import 'package:rootgist/features/settings/notices.dart';
import 'package:rootgist/features/settings/settings_screen.dart';
import 'package:rootgist/debug/widget_gallery.dart';
import 'package:rootgist/design/typography.dart';
import 'package:rootgist/design/theme.dart';
import 'package:rootgist/design/tokens.dart';
import 'package:rootgist/design/widgets/rg_buttons.dart';
import 'package:rootgist/design/widgets/rg_row_head.dart';
import 'package:rootgist/design/widgets/rg_segmented.dart';
import 'package:flutter/semantics.dart';
import 'package:rootgist/features/explore/explore_screen.dart';
import 'package:rootgist/features/explore/official_news.dart';
import 'package:rootgist/features/explore/date_groups.dart';
import 'package:rootgist/features/explore/x_posts.dart';
import 'package:rootgist/features/common/collect_schedule.dart';
import 'package:rootgist/features/common/term_text.dart';
import 'package:rootgist/features/home/home_screen.dart';
import 'package:rootgist/features/home/home_sections.dart';
import 'package:rootgist/features/home/briefing.dart';
import 'package:rootgist/features/paper/paper_screen.dart';
import 'package:rootgist/features/reader/reader_screen.dart';
import 'package:rootgist/features/reader/term_sheet.dart';
import 'package:rootgist/main.dart';
import 'package:rootgist/analytics/posthog_sink.dart';

// 에셋 읽기는 실제 I/O라 fake async 안에서 시작하면 끝나지 않고, rootBundle이 그 미완료 Future를 캐시해
// 다음 테스트까지 막는다. 첫 프레임(initState의 fixture 읽기)을 실제 async 영역에서 띄운다.
Future<void> pumpApp(WidgetTester tester) async {
  router.go('/home'); // 전역 라우터·북마크라 이전 테스트 상태가 남는다
  bookmarks.value = {};
  readerDefaultMode.value = ReaderMode.together;
  readerScale.value = 1.0;
  exploreTab.value = 0;
  newsTab.value = 0;
  modelsFresh.value = false;
  githubPeriod.value = 0;
  fixtureMode.value = FixtureMode.normal;
  exploreJump.value = null;
  // 새 글 점은 기본으로 끈다(따로 확인하는 테스트에서 켠다)
  newSince = DateTime.utc(2100);
  readItems.value = {};
  modelsSeen.value = {};
  newsSeenAt.value = null;
  tipsSeen.value = {tipReader, tipNews};
  clock = DateTime.now;
  // 홈 키워드 칩이 바로 사전을 부른다: 지난 테스트의 끝나지 않은 요청을 물려받지 않게 새로, 실제 비동기에서 미리 받아 둔다
  resetDictionary();
  await tester.runAsync(dictionary);
  // GitHub 순위는 소식 HOT 칸 카드 줄이 탭을 누른 뒤(fake async) 처음 읽는다: 실제 비동기에서 미리 읽어 캐시를 채워 둔다
  await tester.runAsync(() => rootBundle.loadString('fixtures/github_rankings.json'));
  await tester.runAsync(() => rootBundle.loadString('fixtures/x_posts.json')); // X 글도 같은 이유로
  resetXPerks();
  await tester.runAsync(() async {
    await tester.pumpWidget(const RootgistApp());
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pumpAndSettle();
}

// 옆으로 밀어 칸이 미끄러져 넘어가는 동안의 프레임도 실제 async 영역에서 그린다. 넘기는 중에 새로 만들어지는
// 칸(옆 칸 미리 만들기 포함)의 fixture 읽기가 fake async 안에서 시작되면 끝나지 않는다.
Future<void> slide(WidgetTester tester) => tester.runAsync(() async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
});

// 화면 이동 뒤 새 화면의 fixture 읽기도 같은 이유로 실제 async 영역에서 프레임을 그린다.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pumpAndSettle();
}

// 상세 본문은 ListView의 지연 생성 대상이라, 아래쪽 내용은 스크롤한 뒤 검사한다.
Future<void> revealPaperContent(WidgetTester tester, Finder finder) async {
  final scrollable = find.descendant(of: find.byType(PaperScreen), matching: find.byType(Scrollable)).first;
  expect(tester.getSize(scrollable).height, greaterThan(0), reason: '논문 dock 위에 본문을 읽고 스크롤할 공간이 있어야 한다.');
  await tester.scrollUntilVisible(finder, 300, scrollable: scrollable);
}

// 날짜 묶음의 접힌 주·달 머리와 날짜 줄을 모두 펼친다(지난 글은 날짜 줄 뒤에 접혀 있다)
Future<void> openDates(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    final closed = find.descendant(
      of: find.byWidgetPredicate((w) => w is DateGroups),
      matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.expanded == false && w.properties.label != null || w is DateHeader && !w.open && w.onTap != null),
    );
    if (closed.evaluate().isEmpty) return;
    await Scrollable.ensureVisible(tester.element(closed.first), alignment: 0.3); // 아래 탭 바에 가리지 않게
    await tester.tap(closed.first);
    await tester.pumpAndSettle();
  }
}

void main() {
  // 앱 시작과 같이 저장값을 한 번 읽고, 이후 변경을 저장하는 리스너를 단다.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'bookmarks': jsonEncode([Bookmark('0000.00002', '저장된 논문', DateTime(2026, 10, 15)).toJson()]),
      'settings.readerMode': 'original',
      'settings.readerScale': 1.15,
      // 처음 안내·도움말은 본 것으로(따로 확인하는 테스트에서 비운다)
      'guide.onboardingDone.v1': true,
      'guide.tipsSeen': [tipReader, tipNews],
    });
    await initStorage();
  });

  test('M3: 저장값을 읽어 오고, 바뀌면 바로 저장한다(Q12)', () async {
    // setUpAll에서 읽은 값(아직 pumpApp 전)
    expect(bookmarks.value['0000.00002']!.savedAt, DateTime(2026, 10, 15));
    expect(readerDefaultMode.value, ReaderMode.original);
    expect(readerScale.value, 1.15);

    toggleBookmark('0000.00001', '추론 시점 연산의 효율적 확장');
    readerScale.value = 0.9;
    final prefs = await SharedPreferences.getInstance();
    expect((jsonDecode(prefs.getString('bookmarks')!) as List).map((j) => j['paper_id']), containsAll(['0000.00001', '0000.00002']));
    expect(prefs.getDouble('settings.readerScale'), 0.9);
  });

  testWidgets('분석은 기본 거부이며 설정에서 변경한 동의를 로컬에 보존한다', (tester) async {
    analyticsCollectionEnabled.value = false;
    await pumpApp(tester);
    router.go('/settings');
    await settle(tester);
    final toggle = find.byKey(const ValueKey('analytics-collection'));
    await tester.ensureVisible(toggle);
    expect(tester.widget<Switch>(toggle).value, false);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(analyticsCollectionEnabled.value, true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('settings.analyticsConsent.v1'), true);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(prefs.getBool('settings.analyticsConsent.v1'), false);
  });

  testWidgets('M3: 모드를 바꿔도 맨 위에 걸친 문장 쌍이 제자리', (tester) async {
    tester.view.physicalSize = const Size(390, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    router.push('/paper/0000.00001/reader?s=A03');
    await settle(tester);

    final pair = find.ancestor(of: find.textContaining('We evaluate', findRichText: true), matching: find.byType(Column)).first;
    final before = tester.getTopLeft(pair).dy;
    expect(before, lessThan(200)); // ?s=A03 으로 스크롤되어 위쪽에 있다
    await tester.tap(find.text('원문'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(pair).dy, moreOrLessEquals(before, epsilon: 1));
  });
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
    expect(all.chips, ['llm', 'agent', 'vision', 'optimization']); // 영상 분할은 multimodal이 아니라 vision(p2 v0.6.2)

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

    expect(find.text(keepAll('6편이 올라왔어요')), findsOneWidget); // 홈은 3편만 미리 보여 주고 나머지는 「더보기」로

    await tester.tap(find.bySemanticsLabel('북마크에 저장').first);
    await tester.pump();
    expect(bookmarks.value.keys, ['0000.00001']);

    await tester.tap(find.text(keepAll('소수 예시 기반 영상 분할의 일반화 성능 분석')));
    await settle(tester);
    expect(find.byType(PaperScreen), findsOneWidget);
    await revealPaperContent(tester, find.bySemanticsLabel('arXiv에서 원문 열기'));
    expect(find.text('arXiv · 0000.00002'), findsOneWidget);

    // P1: 외부 링크 행은 밑줄과 동작을 말하는 화면 읽기 문구(arXiv·HF).
    expect(find.text('Hugging Face'), findsOneWidget);
    for (final label in ['arXiv에서 원문 열기', 'Hugging Face에서 논문 페이지 열기']) {
      final link = find.bySemanticsLabel(label);
      expect(link, findsOneWidget);
      expect(tester.getSemantics(link).getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    }
    for (final label in ['원문 출처', '논문 페이지']) {
      expect(tester.widget<Text>(find.text(label)).style!.decoration, TextDecoration.underline);
    }
  });

  testWidgets('P5: 추천 카드는 버튼 없이 카드 전체가 S02로, 북마크는 이동 없이 토글', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);

    expect(find.text('자세히 읽기'), findsNothing);
    // 추천 카드의 북마크(카드 안 첫 북마크)는 이동하지 않는다
    await tester.tap(find.bySemanticsLabel('북마크에 저장').first);
    await tester.pump();
    expect(bookmarks.value.keys, ['0000.00001']);
    expect(find.byType(PaperScreen), findsNothing);

    await tester.tap(find.text(keepAll('추론 시점 연산의 효율적 확장')));
    await settle(tester);
    expect(find.byType(PaperScreen), findsOneWidget);
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
    final evidence = find.bySemanticsLabel('원문 근거, 초록 4번째 문장');
    await revealPaperContent(tester, evidence);
    expect(evidence, findsOneWidget);
    expect(find.text('게시 조직'), findsNothing);

    await tester.tap(evidence);
    await tester.pumpAndSettle();
    expect(find.text('핵심 내용 3의 근거'), findsOneWidget);
    expect(find.text('On the example benchmark, the method uses 30% less compute at matched accuracy.'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('닫기')); // 시트 손잡이(보이는 닫기 버튼은 없다)
    await tester.pumpAndSettle();
    expect(find.text('핵심 내용 3의 근거'), findsNothing);

    router.push('/paper/0000.00004');
    await settle(tester);
    await revealPaperContent(tester, find.text('Example Lab'));
    expect(find.text('Example Lab'), findsOneWidget);
  });

  test('S03: 용어 하이라이트는 highlight=true만, 용어당 처음 1회', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final p = await repository.getPaper('0000.00001');
    final h = firstHighlights(p);
    expect(h.keys, unorderedEquals(['A01', 'A03'])); // Benchmark(highlight=false)는 없음
    expect(h['A01']!.single.$2.term, 'inference-time compute');
    expect(h['A01']!.single.$1, 'For large language models, '.length);

    // G2: 번역문에서 찾는다. 사전 대응어가 없어도 이 논문 번역문의 표기(term_ko_span)가 있으면 강조한다
    final ko = firstHighlights(p, korean: true);
    expect(ko.keys, unorderedEquals(['A01', 'A03', 'A04']));
    expect(ko['A01']!.single.$3, '추론 시점 연산');
    expect(ko['A01']!.single.$1, '대규모 언어 모델에서 '.length);
    expect(ko['A03']!.single.$3, '연산 예산');

    // 번역문에 영문 표기가 그대로 남은 용어(SFT)는 표기 없이도 찾는다. 낱말 안(RAGAS의 RAG)은 아니다
    final p3 = PaperDetail.fromJson({
      'paper_id': 'y', 'title_en': 'T', 'authors': ['A'], 'published_at': '2026-10-18', 'hf_url': '', 'arxiv_url': '',
      'ai_status': 'ready',
      'sentences': [{'sentence_id': 'A01', 'kind': 'text', 'text': 'We apply SFT and RAG.', 'translation_ko': 'RAGAS로 평가하고 SFT를 적용한다.'}],
      'glossary': [
        {'term': 'SFT', 'definition_ko': '정의.', 'sentence_ids': ['A01'], 'highlight': true},
        {'term': 'RAG', 'definition_ko': '정의.', 'sentence_ids': ['A01'], 'highlight': true},
      ],
    });
    final ko3 = firstHighlights(p3, korean: true)['A01']!;
    expect(ko3.map((h) => h.$3), ['SFT']);
    expect(ko3.single.$1, 'RAGAS로 평가하고 '.length);

    // 번역문 표기가 대응어와 다르면 논문별 표기(term_ko_span)로 찾는다(동결된 디코더 ↔ 고정 디코더)
    final p2 = PaperDetail.fromJson({
      'paper_id': 'x', 'title_en': 'T', 'authors': ['A'], 'published_at': '2026-10-18', 'hf_url': '', 'arxiv_url': '',
      'ai_status': 'ready',
      'sentences': [{'sentence_id': 'A01', 'kind': 'text', 'text': 'We use a frozen decoder.', 'translation_ko': '동결된 디코더를 쓴다.'}],
      'glossary': [{'term': 'frozen decoder', 'definition_ko': '정의.', 'sentence_ids': ['A01'], 'highlight': true,
                    'term_ko': '고정 디코더', 'term_ko_span': '동결된 디코더'}],
    });
    expect(firstHighlights(p2, korean: true)['A01']!.single.$3, '동결된 디코더');

    // 관리자가 넣은 한국어 별칭: 번역문 표기를 아직 못 정했어도 별칭으로 찾는다(논문 상세 요약·핵심 내용도 같은 규칙)
    final p4 = PaperDetail.fromJson({
      'paper_id': 'z', 'title_en': 'T', 'authors': ['A'], 'published_at': '2026-10-18', 'hf_url': '', 'arxiv_url': '',
      'ai_status': 'ready',
      'sentences': [{'sentence_id': 'A01', 'kind': 'text', 'text': 'We use a frozen encoder.', 'translation_ko': '동결 인코더를 쓴다.'}],
      'glossary': [{'term': 'frozen encoder', 'definition_ko': '정의.', 'sentence_ids': ['A01'], 'highlight': true,
                    'term_ko': '고정 인코더', 'aliases': ['frozen encoders', '동결 인코더']}],
    });
    expect(firstHighlights(p4, korean: true)['A01']!.single.$3, '동결 인코더');
    expect(findHighlights('요약: 동결 인코더로 학습해요.', p4.glossary).single.$3, '동결 인코더');
  });

  testWidgets('iOS: 왼쪽 가장자리에서 밀면 S03 → S02 → 홈으로 뒤로 간다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    // 전역 rgTheme은 처음 만든 테스트의 플랫폼(Android)을 들고 있어, iOS 전환을 쓰도록 테마만 바꿔 다시 띄운다.
    await tester.pumpWidget(MaterialApp.router(theme: rgTheme.copyWith(platform: TargetPlatform.iOS), routerConfig: router));
    await tester.pumpAndSettle();

    router.push('/paper/0000.00001');
    await settle(tester);
    router.push('/paper/0000.00001/reader');
    await settle(tester);
    expect(find.byType(ReaderScreen), findsOneWidget);

    await tester.dragFrom(const Offset(5, 400), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsNothing);
    expect(find.byType(PaperScreen), findsOneWidget);

    await tester.dragFrom(const Offset(5, 400), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.byType(PaperScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('S03: 문장 번호·쌍 구분선, 「함께」 영문은 세로선 + 14/22(iOS QA 디자인)', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    router.push('/paper/0000.00001/reader');
    await settle(tester);

    final en = find.byWidgetPredicate((w) => w is Text && w.textSpan?.style?.fontFamily == RgText.serif);
    expect(find.text('3'), findsOneWidget); // A03 문장 번호
    expect(find.byType(Divider), findsWidgets);
    expect(tester.widget<Text>(en.first).textSpan!.style!.fontSize, 15); // 리디자인: Reader EN 15/24
    // 원문은 번역 아래 왼쪽 세로선 안에
    expect(find.ancestor(of: en.first, matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border != null)), findsOneWidget);
  });

  testWidgets('하위 화면은 배경이 불투명하다(전환 중 뒤 화면이 비치지 않게)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);

    for (final (path, screen) in [
      ('/settings/source', DataSourceScreen),
      ('/settings/privacy', PrivacyScreen),
      ('/explore/2026-10-18', HomeScreen),
    ]) {
      router.go(path);
      await settle(tester);
      final opaque = find.ancestor(
        of: find.byType(screen).last,
        matching: find.byWidgetPredicate((w) => w is ColoredBox && w.color == RgColors.bgApp),
      );
      expect(opaque, findsWidgets, reason: path);
    }
  });

  testWidgets('P8d: 탐색은 옆으로 밀어 논문 ↔ 공식 소식, 발표 | 업데이트, 요약·핵심 내용과 근거', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    router.go('/explore');
    await settle(tester);
    expect(find.text('지난 논문'), findsOneWidget);

    // 왼쪽으로 밀면 공식 소식
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await slide(tester); // 칸 넘김 애니메이션
    await settle(tester);
    await openDates(tester);
    // 발표 목록은 제목과 출처·한국 날짜만 보인다(UTC 17시는 KST 다음 날).
    expect(find.text('OpenAI · 10월 18일'), findsOneWidget);
    expect(find.text(keepAll('가상의 예시 API를 소개합니다')), findsOneWidget);
    expect(find.text('Introducing a fictional example API'), findsNothing);
    expect(find.text('가상의 예시 API를 소개하는 가상 글이에요. 실제 내용이 아니에요.'), findsNothing); // 요약은 상세에서
    expect(find.textContaining('10월', findRichText: true), findsWidgets); // 지난달 글은 한 달로 묶는다
    expect(find.text('Google DeepMind · 10월 16일'), findsOneWidget);
    expect(find.text(keepAll('Fictional screening research for tests')), findsOneWidget); // 번역 없으면 원문만
    expect(find.text('Claude Code'), findsNothing); // 릴리스는 「업데이트」에

    // 누르면 상세: 원제·AI 요약·핵심 내용과 근거
    await tester.tap(find.text(keepAll('가상의 예시 API를 소개합니다')));
    await settle(tester);
    expect(find.text('Introducing a fictional example API'), findsOneWidget);
    // AI 요약: 공용 용어 사전의 용어(API)가 강조되고, 누르면 사전의 뜻
    expect(find.textContaining(keepAll('실제 내용이 아니에요.'), findRichText: true), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('용어 설명: API'));
    await tester.pumpAndSettle();
    expect(find.text('뜻'), findsOneWidget);
    expect(find.text('용어 사전 · 논문 3편에서 쓰임'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('근거 · 원문 소개문'), findsNWidgets(2)); // OpenAI는 피드 소개문이 근거
    router.pop();
    await settle(tester);

    await tester.tap(find.text('업데이트'));
    await tester.pumpAndSettle();
    await openDates(tester);
    // 업데이트는 도구 이름·변경 제목·버전·한국 날짜. 근거·변경 목록은 상세에서
    expect(find.text('(v0.0.1~v0.0.3) · 10월 18일'), findsOneWidget);
    expect(find.text(keepAll('Claude Code')), findsOneWidget);
    expect(find.text(keepAll('가상의 예시 기능을 이제 쓸 수 있어요')), findsOneWidget);
    expect(find.text('근거 · 원문 1번째 문단'), findsNothing);
    // 출처 칩 색: SDK 릴리스도 회사 색(보관함 저장 이름도 같은 색)
    expect(brandOf('openai_sdk'), brandOf('openai'));
    expect(brandOf('Anthropic Python SDK'), brandOf('anthropic'));
    expect(brandOf('nvidia_dev'), (RgBrand.nvidia.background, RgBrand.nvidia.foreground)); // 연한 면 + 같은 색 계열 진한 글자
    expect(brandOf('Meta'), (RgBrand.meta.background, RgBrand.meta.foreground));
    expect(brandOf('xai_sdk'), brandOf('xAI'));

    // 오른쪽으로 밀면 발표, 한 번 더 밀면 논문(공식 소식 안의 발표 | 업데이트도 밀기 순서에 들어간다)
    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
    await slide(tester);
    await settle(tester);
    expect(newsTab.value, 0);
    expect(find.text('Claude Code · 릴리스 · 10월 18일'), findsNothing);
    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
    await slide(tester);
    await settle(tester);
    expect(find.text('지난 논문'), findsOneWidget);
  });

  testWidgets('P9: 탐색 「모델」 칸은 HF 트렌딩 순위, 누르면 제작사 강점·점수, 카드가 없으면 안내', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    router.go('/explore');
    await settle(tester);
    await tester.tap(find.text('모델'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    } // 칸 넘김이 끝나야 모델 칸이 그려지고 불러오기를 시작한다
    await settle(tester);
    expect(find.text('example-coder'), findsOneWidget);
    // 트렌딩 카드는 순위와 모델 사양, 만든 곳은 상세의 「한눈에」에서 확인한다.
    expect(find.text('400억 파라미터 텍스트 생성 모델'), findsOneWidget);
    expect(find.text('example-video'), findsOneWidget);
    for (final rank in ['1위', '2위']) {
      expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == rank), findsOneWidget);
    }

    await tester.tap(find.text('example-coder'));
    await settle(tester);
    expect(find.text(keepAll('Hugging Face 트렌딩 1위')), findsOneWidget);
    expect(find.text(keepAll('example-lab 공개 · 400억 파라미터 텍스트 생성 모델')), findsOneWidget); // 상세 「한눈에」는 그대로
    expect(find.text('제작사가 내세운 강점'), findsOneWidget);
    expect(find.textContaining(keepAll('가상의 코딩'), findRichText: true), findsOneWidget);
    expect(find.bySemanticsLabel('용어 설명: agent'), findsOneWidget); // 강점 문장에도 사전 용어 강조
    expect(find.text('함께 오른 변형 1개'), findsOneWidget);
    expect(find.text('example-coder-GGUF'), findsOneWidget);
    // 「한눈에」 하는 일·크기·라이선스 3칸(리디자인). 칸들은 같은 줄 위에 나란히
    final tops = [
      for (final v in ['텍스트 생성', '400억 파라미터', 'Apache-2.0'])
        tester.getTopLeft(find.text(keepAll(v))).dy,
    ];
    expect(tops.toSet().length, 1, reason: '$tops');
    expect(find.text('SWE-bench Verified'), findsOneWidget);
    expect(find.text(keepAll('12.3%')), findsOneWidget);
    router.pop();
    await settle(tester);

    await tester.tap(find.text('example-video'));
    await settle(tester);
    expect(find.text(keepAll(byLine('제작사가 모델 카드에 강점이나 평가 결과를 밝히지 않았어요. 연결된 논문에서 확인해 보세요.'))), findsOneWidget);
    expect(find.text('arXiv · 0000.00001'), findsOneWidget);
  });

  testWidgets('홈 하이라이트: 논문 3편·공식 발표·업데이트·모델, 「더 보기」는 탐색의 그 칸으로', (tester) async {
    tester.view.physicalSize = const Size(390, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    await settle(tester);
    expect(find.text('오늘의 주요 논문'), findsOneWidget);
    // 디자이너 시안 home_re(2026-10-31): 주요 소식 → (개발자 화제) → 오늘의 논문 → 바뀐 도구 → 모델 트렌드 순위.
    // fixture 소식은 오래돼 「최근 소식」. 날짜 헤드라인·요약 배지는 없다
    expect(find.text(keepAll('새 소식이 없어요')), findsNothing);
    expect(find.text(keepAll('최근 소식')), findsOneWidget);
    expect(find.byType(HomeStoryRow), findsNWidgets(3));
    expect(find.text(keepAll('오늘의 논문')), findsOneWidget);
    expect(find.text(keepAll('바뀐 도구')), findsOneWidget);
    expect(find.text(keepAll('모델 트렌드 순위')), findsOneWidget);
    expect(find.bySemanticsLabel('더보기'), findsNWidgets(4)); // 칸마다(소식·논문·바뀐 도구·모델)
    // 바뀐 도구: 회사 색 카드에 시각 → 도구 이름 → 「업데이트 3건 (v0.0.1~v0.0.3)」
    expect(find.byType(HomeUpdateCard), findsNWidgets(2));
    expect(find.text(keepAll('Claude Code')), findsOneWidget);
    // 모델: 3장, 큰 순위 숫자
    expect(find.byType(HomeModelCard), findsNWidgets(3));
    expect(find.text('example-coder'), findsOneWidget);
    // 북마크는 논문 3 + 바뀐 도구 2(공유는 상세 화면에서)
    expect(find.bySemanticsLabel('공유'), findsNothing);
    expect(find.bySemanticsLabel('북마크에 저장'), findsNWidgets(3 + 2));

    // 바뀐 도구를 저장하면 보관함에 「공식 소식」으로
    await tester.tap(find.descendant(of: find.byType(HomeUpdateCard).first, matching: find.bySemanticsLabel('북마크에 저장')));
    await tester.pump();
    expect(bookmarks.value.values.last.kind, 'news');

    // 홈에서 연 상세는 뒤로 가면 홈으로(탐색으로 가지 않는다)
    await tester.tap(find.text('example-coder'));
    await settle(tester);
    expect(find.text('제작사가 내세운 강점'), findsOneWidget);
    // 쉘 밖 화면도 Material 위에 그린다(없으면 글자 밑에 노란 두 줄)
    expect(find.ancestor(of: find.text('제작사가 내세운 강점'), matching: find.byType(Material)), findsWidgets);
    router.pop();
    await settle(tester);
    expect(find.text(keepAll('모델 트렌드 순위')), findsOneWidget);

    Finder more(String section) => find.descendant(of: find.widgetWithText(HomeSection, keepAll(section)), matching: find.bySemanticsLabel('더보기'));
    await tester.tap(more('바뀐 도구'));
    await settle(tester);
    expect(find.widgetWithText(ExploreSectionTabs, '업데이트'), findsOneWidget);
    expect(newsTab.value, 1);
    await openDates(tester);
    expect(find.text(keepAll('Claude Code')), findsOneWidget);
    // 업데이트 행의 제목을 눌러도 소식 상세로(릴리스는 AI 요약이 없어 공지를 연다).
    final notice = find.text(keepAll('가상의 예시 기능을 이제 쓸 수 있어요'));
    await Scrollable.ensureVisible(tester.element(notice), alignment: 0.3); // 아래 탭 바에 가리지 않게
    await tester.pumpAndSettle();
    await tester.tap(notice);
    await settle(tester);
    expect(find.text('AI 요약'), findsWidgets);
    expect(find.bySemanticsLabel('원문 열기'), findsOneWidget); // 소식 상세 상단 바
    router.pop();
    await settle(tester);

    router.go('/home');
    await settle(tester);
    await tester.tap(more('모델 트렌드 순위'));
    await settle(tester);
    expect(find.text(keepAll(byLine('요즘 Hugging Face에서 주목받는 모델이에요. 순서는 Hugging Face의 트렌딩 순위예요.'))), findsOneWidget);

    router.go('/library');
    await settle(tester);
    expect(find.textContaining(keepAll('공식 소식 · ')), findsOneWidget); // 보관함 머리 줄: 출처 칩 + 「공식 소식 · 저장일」
  });

  testWidgets('새 글 점: 안 연 공지·소식에만, 열면 사라진다(설정 공지 행·탐색 칸·소식 행, 탭바에는 없음)', (tester) async {
    tester.view.physicalSize = const Size(390, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    // fixture 날짜(마지막 소식 10월 18일)에 맞춘 시계(새 글은 하루 안), 기준 시각은 10월 1일
    clock = () => DateTime.utc(2026, 10, 18, 20);
    newSince = DateTime.utc(2026, 10, 1);
    readItems.value = {...readItems.value}; // 다시 그리기
    await settle(tester);

    final notices = (await tester.runAsync(loadNotices))!; // 실제 파일 읽기는 runAsync 안에서
    final fresh = [for (final n in notices) if (n.isNew) n];
    expect(fresh, isNotEmpty);
    expect(find.bySemanticsLabel('설정, 새 글'), findsNothing); // 탭바에는 점을 달지 않는다(피드백)

    // 설정 탭 안의 공지사항 행에만 점. 공지를 모두 열면 사라진다
    router.go('/settings');
    await settle(tester);
    expect(find.byType(RgNewDot), findsOneWidget);
    for (final n in notices) {
      markRead(n.key);
    }
    await tester.pump();
    expect(find.byType(RgNewDot), findsNothing);
    router.go('/home');
    await settle(tester);

    // 홈의 공식 발표 행: 하루 안의 안 연 글에 「새 글」 글자(출처 배지가 회사 색이라 점 대신), 상세를 열면 그 글만 사라진다
    // 읽으면 「새 글」은 작아지며 사라진다(위젯은 남고 visible만 꺼진다)
    final dots = find.descendant(of: find.byType(HomeStoryRow), matching: find.byWidgetPredicate((w) => w is RgNewLabel && w.visible));
    final before = dots.evaluate().length;
    expect(before, greaterThan(0));
    await tester.tap(find.descendant(of: find.byType(HomeStoryRow), matching: find.byWidgetPredicate((w) => w is RgNewLabel && w.visible)).first);
    await settle(tester);
    router.pop();
    await settle(tester);
    expect(dots.evaluate().length, before - 1);

    // 하루가 지나면 안 열었어도 점이 없다
    clock = () => DateTime.utc(2026, 12, 1);
    readItems.value = {...readItems.value};
    await tester.pump();
    expect(dots, findsNothing);
  });

  test('날짜 묶음: 최근 7일은 하루, 이번 달은 주, 지난달부터 달, 지난해부터 해(한국 시간)', () {
    final now = DateTime.utc(2026, 11, 20, 3); // KST 11월 20일(금) 정오
    DateUnit unit(DateTime at) => dateKey(at, now).$1;
    expect(unit(DateTime.utc(2026, 11, 20)), DateUnit.day);
    expect(unit(DateTime.utc(2026, 11, 14)), DateUnit.day); // 6일 전
    expect(unit(DateTime.utc(2026, 11, 13)), DateUnit.week); // 7일 전, 이번 달
    expect(unit(DateTime.utc(2026, 10, 31)), DateUnit.month); // 지난달
    expect(unit(DateTime.utc(2025, 12, 31)), DateUnit.year); // 지난해(아직 1년치가 없어 기능만)
    // KST 월요일 0시 직전·직후(UTC 일요일 15시)
    expect(weekStart(DateTime.utc(2026, 11, 8, 14, 59)), DateTime.utc(2026, 11, 2));
    expect(weekStart(DateTime.utc(2026, 11, 8, 15)), DateTime.utc(2026, 11, 9));
    final items = [
      DateTime.utc(2026, 11, 20, 1), DateTime.utc(2026, 11, 19), DateTime.utc(2026, 11, 10),
      DateTime.utc(2026, 11, 3), DateTime.utc(2026, 10, 5), DateTime.utc(2026, 10, 20), DateTime.utc(2025, 6, 1),
    ];
    final groups = groupByDate(items, (d) => d, now);
    expect([for (final g in groups) dateLabel(g, now)], [
      ('오늘', null), ('어제', null), ('지난주', '11월 9일 ~ 11월 15일'), ('11월 2일 ~ 11월 8일', null), ('2026년 10월', null), ('2025년', null),
    ]);
    expect(groups[4].rows, [DateTime.utc(2026, 10, 5), DateTime.utc(2026, 10, 20)]); // 묶음 안은 받은 순서
    expect(dateLabel(groupByDate([DateTime.utc(2026, 11, 16)], (d) => d, now).single, now), ('11월 16일 월요일', null));
  });

  testWidgets('날짜 묶음 모양: 최근 7일은 글 카드, 지난 주·달은 「지난 논문」처럼 날짜 줄, 날짜 줄을 누르면 그날 글이 펼쳐진다', (tester) async {
    final now = DateTime.utc(2026, 11, 20, 3);
    final items = [
      (DateTime.utc(2026, 11, 19), 'A'), (DateTime.utc(2026, 10, 29), 'B'), (DateTime.utc(2026, 10, 29, 2), 'C'), (DateTime.utc(2026, 10, 5), 'B'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DateGroups<(DateTime, String)>(
            items: items, at: (i) => i.$1, tag: (i) => i.$2, now: now,
            builder: (context, rows) => Column(children: [for (final r in rows) Text('글 ${r.$2} ${r.$1.day}')]),
          ),
        ),
      ),
    ));
    expect(find.text('글 A 19'), findsOneWidget); // 어제: 카드 그대로
    expect(find.text('2일치'), findsOneWidget); // 2026년 10월: 날짜 줄 두 개(29일·5일)
    expect(find.text('글 B 29'), findsNothing);
    await tester.tap(find.text('2026년 10월', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('2건'), findsOneWidget); // 29일 목요일 2건
    expect(find.text('B 외'), findsOneWidget); // 같은 수면 앞의 이름 + 외
    expect(find.text('목요일'), findsOneWidget);
    await tester.tap(find.text('29'));
    await tester.pumpAndSettle();
    expect(find.text('글 B 29'), findsOneWidget);
    expect(find.text('글 C 29'), findsOneWidget);
    expect(find.text('글 B 5'), findsNothing); // 다른 날은 접힌 채
  });

  test('새 글 규칙: 기준 시각 전·하루 지난 글·읽은 글은 새 글이 아니다', () {
    clock = () => DateTime.utc(2026, 10, 20);
    newSince = DateTime.utc(2026, 10, 10);
    readItems.value = {'a'};
    expect(isNew('b', DateTime.utc(2026, 10, 19, 1)), isTrue);
    expect(isNew('a', DateTime.utc(2026, 10, 19, 1)), isFalse); // 읽음
    expect(isNew('b', DateTime.utc(2026, 10, 18, 23)), isFalse); // 하루 지남
    expect(isNew('b', DateTime.utc(2026, 10, 9)), isFalse); // 기준 시각 전
    expect(isNew('b', DateTime.utc(2026, 10, 12)), isFalse); // 8일 지남
    expect(Notice('t', '2026.10.27', []).publishedAt, DateTime.utc(2026, 10, 26, 15)); // KST 0시
    clock = DateTime.now;
    readItems.value = {};
  });

  testWidgets('짧은 원문(소개문 한 줄)은 「원문 소개문」으로, 이름이 겹치는 관련 소식을 잇는다', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    router.push('/news/${Uri.encodeComponent('https://example.com/fixture/news-thin')}');
    await settle(tester);
    expect(find.text('원문 소개문'), findsOneWidget);
    expect(find.text('AI 요약'), findsNothing); // 요약이 있는 척하지 않는다
    expect(find.text(keepAll('가상의 exa-7.5-nova를 모두에게 열어요.')), findsOneWidget);
    expect(find.textContaining(keepAll('소개문만 옮겼어요')), findsOneWidget);
    // 관련 소식: 릴리스의 같은 이름이 나오는 핵심 내용을 함께 보여 준다
    expect(find.text('관련 소식'), findsOneWidget);
    expect(find.byType(RelatedRow), findsOneWidget);
    expect(find.text(keepAll('가상의 exa-7.5-nova 모델 식별자가 추가됐어요')), findsOneWidget);
  });

  test('바뀐 도구 버전 태그: 마지막 버전과 건수, 버전이 없으면 건수만, 공지는 「공지」', () {
    OfficialNews n(String kind, String title) => OfficialNews.fromJson({
      'id': 'x', 'source': 's', 'source_label': 'S', 'kind': kind, 'title_en': title, 'url': 'u',
      'published_at': '2026-10-24T00:00:00Z', 'key_points': [],
    });
    expect(releaseTag(n('release', 'Claude Code v2.1.304~v2.1.310 (7 releases)')), 'v2.1.310 · 7건');
    expect(releaseTag(n('release', 'OpenAI Python SDK v3.37.0 (1 release)')), 'v3.37.0 · 1건');
    expect(releaseTag(n('release', 'Claude API release notes (19 changes)')), '19건');
    expect(releaseTag(n('notice', 'Fictional example feature is now available')), '공지');
  });

  test('P8d: 근거 링크는 원문 구절 위치로(#:~:text=), 구절이 없으면 글 주소', () {
    final n = OfficialNews.fromJson({
      'source': 's', 'source_label': 'S', 'title_en': 't', 'published_at': '2026-10-18T00:00:00Z', 'url': 'https://e.com/a',
      'key_points': [{'text': '가', 'para': 1, 'quote': 'two words'}, {'text': '나', 'para': 2}],
    });
    expect(n.evidenceUrl(n.keyPoints[0]), 'https://e.com/a#:~:text=two%20words');
    expect(n.evidenceUrl(n.keyPoints[1]), 'https://e.com/a');
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

    await tester.tap(find.bySemanticsLabel('용어 설명: compute budget').first); // 영문·번역문 양쪽
    await tester.pumpAndSettle();
    expect(find.text('이 논문에서의 뜻'), findsOneWidget);
    expect(find.text(keepAll('학습이나 추론에 쓸 수 있도록 미리 정해 둔 계산량의 한도.')), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('닫기')); // 시트 손잡이(보이는 닫기 버튼은 없다)
    await tester.pumpAndSettle();

    // 함께 모드: 같은 용어가 영문·한국어 양쪽에 강조되고, 한국어 쪽을 눌러도 C02에 대응어가 나온다(G1·G2)
    expect(find.bySemanticsLabel('용어 설명: inference-time compute'), findsNWidgets(2));
    await tester.tap(find.bySemanticsLabel('용어 설명: inference-time compute').first);
    await tester.pumpAndSettle();
    expect(find.text('추론 시점 연산'), findsWidgets);
    await tester.tap(find.bySemanticsLabel('닫기')); // 시트 손잡이(보이는 닫기 버튼은 없다)
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
    // 큰 날짜 숫자 + 요일 옆에 편수·상태(리디자인)
    expect(find.text(keepAll('수집이 늦어지고 있어요')), findsOneWidget);
    expect(find.text('마지막 정상 수집 09:00'), findsOneWidget);
    await tester.tap(find.text('2026년 9월')); // 지난달은 접혀 있다
    await tester.pumpAndSettle();
    expect(find.text('기타'), findsOneWidget); // 단독이면 「외」 없음
    expect(find.text(keepAll('10월 19일 월요일')), findsNothing); // 오늘 제외

    await tester.tap(find.bySemanticsLabel(RegExp('^10월 18일 일요일')));
    await settle(tester);
    expect(find.bySemanticsLabel('뒤로'), findsOneWidget);
    expect(find.textContaining(keepAll('10월 18일 일요일'), findRichText: true), findsWidgets);
    expect(find.text('10월 18일 주요 논문'), findsOneWidget); // 지난 날짜에는 「오늘의」 대신 그 날짜
    expect(find.text('오늘의 주요 논문'), findsNothing);

    await tester.tap(find.bySemanticsLabel('뒤로'));
    await tester.pumpAndSettle();
    expect(find.text('지난 논문'), findsOneWidget);
  });

  testWidgets('S05: 저장 목록, 해제 → 되돌리기, 전체 비우기', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);

    restoreBookmark(Bookmark('0000.00001', '추론 시점 연산의 효율적 확장', DateTime(2026, 10, 19)));
    restoreBookmark(Bookmark('0000.00003', '보상 모델 없이 선호를 학습하는 정책 최적화', DateTime(2026, 10, 18)));
    router.go('/library');
    await tester.pumpAndSettle();
    expect(find.text('이 기기에 저장한 항목 2개'), findsOneWidget);
    // 통일 머리 줄: 종류 칩(논문) + 출처 · 저장일
    expect(find.text('논문'), findsNWidgets(2));
    expect(find.text(keepAll('arXiv · 10월 19일 저장')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('저장됨, 북마크 해제').first); // 최신순 첫 행 = 10월 19일
    await tester.pump(const Duration(milliseconds: 100)); // 행이 접히는 중(220ms)에는 아직 지우지 않는다
    expect(find.text('이 기기에 저장한 항목 2개'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('이 기기에 저장한 항목 1개'), findsOneWidget);
    await tester.tap(find.text('되돌리기'));
    await tester.pumpAndSettle();
    expect(find.text(keepAll('arXiv · 10월 19일 저장')), findsOneWidget); // 저장일 그대로 복원

    await tester.tap(find.text('전체 비우기'));
    await tester.pumpAndSettle();
    expect(find.text('저장한 항목 2개를 모두 뺄까요?'), findsOneWidget);
    await tester.tap(find.text('모두 빼기'));
    await tester.pumpAndSettle();
    expect(find.text('아직 저장한 게 없어요'), findsOneWidget);
    expect(find.text('전체 비우기'), findsNothing);
  });

  testWidgets('S06: 기본 보기가 S03에 반영, C03·데이터 출처', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);

    router.go('/settings');
    await tester.pumpAndSettle();
    // 설정 행의 값은 오른쪽 끝(카드 안쪽 390 − 24 − 16 = 350)에 맞춘다. 가운데부터 놓이던 회귀를 막는다
    expect(tester.getTopRight(find.text(keepAll(appVersion))).dx, moreOrLessEquals(350, epsilon: 1));
    await tester.tap(find.text('읽기 설정')); // 초록 기본 보기·글자 크기는 하위 화면으로(피드백 13)
    await settle(tester);
    await tester.tap(find.text('원문'));
    await tester.pumpAndSettle();
    expect(readerDefaultMode.value, ReaderMode.original);
    await tester.tap(find.text('크게'));
    await tester.pumpAndSettle();
    expect(readerScale.value, 1.15);
    expect(find.text(keepAll('AI 요약과 초록 번역이 이 크기로 보여요.')), findsOneWidget); // 고른 크기 예시
    router.go('/settings');
    await settle(tester);
    expect(find.text(keepAll('원문 · 크게')), findsOneWidget);

    await tester.tap(find.text('AI 생성 안내'));
    await tester.pumpAndSettle();
    expect(find.text(keepAll(aiNoticeParagraphs.first)), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('닫기')); // 시트 손잡이(보이는 닫기 버튼은 없다)
    await tester.pumpAndSettle();

    await tester.tap(find.text('데이터 출처'));
    await tester.pumpAndSettle();
    expect(find.text(keepAll(DataSourceScreen.paragraphs.first)), findsOneWidget);

    router.push('/paper/0000.00001/reader');
    await settle(tester);
    expect(find.text(keepAll('본 연구는 입력 복잡도에 따라 추론 연산을 동적으로 배분하는 방법을 제안한다.')), findsNothing);
    expect(find.text('We propose a method that dynamically allocates inference compute according to input complexity.'), findsOneWidget);
  });

  test('G13: 처리방침 마크다운 — 앞머리는 빼고 제목·절·목록·문단으로', () {
    final blocks = markdownBlocks('---\ntitle: x\npermalink: /privacy/\n---\n\n# 제목\n\n첫 줄\n이어진 줄\n\n## 1. 절\n\n- 가\n- 나\n');
    expect(blocks, [
      (MdBlock.title, '제목'),
      (MdBlock.paragraph, '첫 줄 이어진 줄'),
      (MdBlock.heading, '1. 절'),
      (MdBlock.bullet, '가'),
      (MdBlock.bullet, '나'),
    ]);
  });

  testWidgets('G13: 설정 → 개인정보 처리방침은 앱 안 화면(docs/privacy.md)', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    router.go('/settings');
    await settle(tester);

    await tester.tap(find.text('개인정보 처리방침'));
    await settle(tester);
    expect(find.text(keepAll('ROOTGIST 개인정보 처리방침')), findsOneWidget);
    expect(find.text(keepAll('2. 기기 안에만 저장되는 정보')), findsOneWidget);
    expect(find.textContaining('permalink'), findsNothing); // 앞머리는 안 보인다
    expect(find.text('웹에서 보기 · $privacyPolicyUrl'), findsOneWidget);
    expect(find.text(keepAll('메일: $contactEmail')), findsOneWidget); // 처리방침 7장과 「문의하기」가 같은 주소
  });

  testWidgets('설정: 이용 안내·오픈소스 라이선스·분석 데이터 삭제 요청(보낸 기록이 없으면 알리고 끝)', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    router.go('/settings');
    await settle(tester);
    // 사용 분석 줄은 한 줄 설명만, 전문(만 14세 미만 안내 포함)은 「보내는 정보 자세히」 시트에(피드백 7번)
    expect(find.textContaining('만 14세 미만이라면 켜지 말아 주세요'), findsNothing);
    await tester.ensureVisible(find.text('보내는 정보 자세히'));
    await tester.tap(find.text('보내는 정보 자세히'));
    await settle(tester);
    expect(find.text(keepAll('만 14세 미만이라면 켜지 말아 주세요.')), findsOneWidget);
    await tester.tapAt(const Offset(195, 20)); // 시트 바깥을 눌러 닫는다
    await settle(tester);

    await tester.tap(find.text('이용 안내'));
    await settle(tester);
    expect(find.text(keepAll('ROOTGIST 이용 안내')), findsOneWidget);
    expect(find.text(keepAll('1. AI가 만든 내용')), findsOneWidget);
    expect(find.text('웹에서 보기 · $termsUrl'), findsOneWidget);
    router.go('/settings');
    await settle(tester);

    await tester.tap(find.text('분석 데이터 삭제 요청'));
    await tester.pumpAndSettle();
    expect(find.text('끄고 삭제 요청하기'), findsOneWidget);
    await tester.tap(find.text('끄고 삭제 요청하기'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50))); // 동의 작업 줄(_consentWork)이 끝나게
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('이 기기에서 보낸 분석 데이터가 없어요. 수집은 꺼져 있어요.'), findsOneWidget); // 테스트 빌드는 분석 미설정
    expect(analyticsCollectionEnabled.value, isFalse);

    await tester.tap(find.text('오픈소스 라이선스'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('G13: 메일 앱을 열 수 없으면 「문의하기」가 주소를 복사하고 알린다', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpApp(tester);
    router.go('/settings');
    await settle(tester);

    // 테스트에는 url_launcher 플랫폼 구현이 없어 메일 앱 열기가 실패한다
    await tester.tap(find.text('문의하기'));
    await settle(tester);
    expect(copied, contactEmail);
    expect(find.text('메일 앱을 열 수 없어 주소를 복사했어요 · $contactEmail'), findsOneWidget);
  });

  testWidgets('공지사항: 설정 → 공지사항은 docs/notices.md, 사용 모델은 배치 설정과 같다', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    router.go('/settings');
    await settle(tester);

    await tester.tap(find.text('공지사항'));
    await settle(tester);
    expect(find.byType(NoticesScreen), findsOneWidget);
    // 목록은 제목·날짜만, 누르면 시트로 내용
    final notices = parseNotices(File('docs/notices.md').readAsStringSync());
    expect(notices.length, greaterThanOrEqualTo(3));
    expect(notices.every((n) => RegExp(r'^\d{4}\.\d{2}\.\d{2}$').hasMatch(n.date)), isTrue); // 제목마다 날짜
    expect(find.text(keepAll('AI가 만든 내용과 사용한 모델')), findsOneWidget);
    expect(find.textContaining(keepAll('DeepSeek V4.1 Flash')), findsNothing);
    await tester.tap(find.text(keepAll('AI가 만든 내용과 사용한 모델')));
    await tester.pumpAndSettle();
    expect(find.textContaining(keepAll('DeepSeek V4.1 Flash')), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('닫기')); // 시트 손잡이(보이는 닫기 버튼은 없다)
    await tester.pumpAndSettle();
    // 공지에 적은 모델이 바뀌면 이 테스트가 알려 준다(worker/llm.py DEEPSEEK_MODELS: 운영 제공처)
    final md = File('docs/notices.md').readAsStringSync();
    final llm = File('worker/llm.py').readAsStringSync();
    expect(llm, contains('DEEPSEEK_FLASH = ("deepseek-flash"'));
    expect(llm, contains('DEEPSEEK_MODELS = (DEEPSEEK_FLASH, DEEPSEEK_FLASH)'));
    expect(llm.contains('"deepseek-v4-pro"'), isFalse); // Pro는 쓰지 않는다(비용)
    expect(md, allOf(contains('DeepSeek 공식 API'), contains('DeepSeek V4.1 Flash')));
    expect(md.contains('Pro'), isFalse);
    // 외부에 보여 주는 결과는 NVIDIA 무료 등급으로 만들지 않는다(NVIDIA는 공식 소식 출처로만 나온다)
    expect(md.contains(RegExp(r'NVIDIA (무료|NIM|API|Build)|build\.nvidia')), isFalse);
    expect(md.contains('본문 전체를 읽'), isFalse); // C03과 같은 원칙
  });

  test('C03 문구: 본문 전체를 읽었다는 표현 금지(7.8)', () {
    for (final p in aiNoticeParagraphs) {
      expect(p.contains('본문'), isFalse, reason: p);
    }
  });

  test('다음 수집 시각: KST 6시 전·15시 전·그 뒤', () {
    expect(nextCollectLabel(DateTime.utc(2026, 11, 8, 20)), '오늘 아침 6시쯤'); // KST 05시
    expect(nextCollectLabel(DateTime.utc(2026, 11, 8, 21)), '오후 3시쯤'); // KST 06시
    expect(nextCollectLabel(DateTime.utc(2026, 11, 9, 5, 59)), '오후 3시쯤'); // KST 14:59
    expect(nextCollectLabel(DateTime.utc(2026, 11, 9, 6)), '내일 아침 6시쯤'); // KST 15시
    expect(nextCollectLabel(DateTime.utc(2026, 11, 9, 14, 59)), '내일 아침 6시쯤'); // KST 23:59
  });

  testWidgets('홈 「다음 수집」 알약: 누르면 하루 두 번 일정과 주말 이유 시트', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    expect(find.byType(NextCollectPill), findsOneWidget); // 홈 맨 위 오른쪽
    // 시각에 따른 글자는 따로 띄워 본다(앱의 1분 타이머는 실제 시간 영역에서 시작돼 가짜 시계로 당길 수 없다)
    clock = () => DateTime.utc(2026, 10, 19, 1); // KST 10시
    addTearDown(() => clock = DateTime.now);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: NextCollectPill()))));
    expect(find.text('다음 수집 오후 3시쯤'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('다음 수집 오후 3시쯤, 수집 일정 보기'));
    await tester.pumpAndSettle();
    expect(find.text('언제 새로 올라와요?'), findsOneWidget);
    expect(find.text('아침 6시쯤'), findsOneWidget);
    expect(find.text('오후 3시쯤'), findsOneWidget);
    expect(find.textContaining(keepAll('arXiv와 Hugging Face')), findsOneWidget);
  });

  testWidgets('P4: 오늘이 0편이면 가장 최근 다이제스트를 안내와 함께 보여 준다', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    await tester.runAsync(() async {
      fixtureMode.value = FixtureMode.empty; // 오늘(10월 19일 월요일)만 0편
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text(keepAll('최근 논문')), findsOneWidget); // 홈 논문 칸 머리(브리핑 아래)
    expect(find.text(keepAll(byLine('주말에는 arXiv와 Hugging Face에 새 논문이 거의 올라오지 않아요. 가장 최근인 10월 18일 일요일 논문을 보여 드려요.'))), findsOneWidget);
    expect(find.text('10월 18일 주요 논문'), findsOneWidget);
    expect(find.descendant(of: find.widgetWithText(HomeSection, keepAll('최근 논문')), matching: find.bySemanticsLabel('더보기')), findsOneWidget);

    // 지연은 대체하지 않고 지금처럼 수집 안내만
    await tester.runAsync(() async {
      fixtureMode.value = FixtureMode.delayed;
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.widgetWithText(HomeSection, keepAll('오늘 논문을 모으는 중이에요')), matching: find.bySemanticsLabel('더보기')), findsNothing);
    expect(find.textContaining(keepAll('모으는'), findRichText: true), findsWidgets);
  });

  testWidgets('M3: fixture 스위치로 8.1 상태 재현(로딩·오류·오프라인·지연·없음), 다시 시도', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);

    // 스켈레톤은 반복 애니메이션이라 pumpAndSettle 대신 pump.
    Future<void> switchTo(FixtureMode m) async {
      await tester.runAsync(() async {
        fixtureMode.value = m;
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
    }

    await switchTo(FixtureMode.loading);
    expect(find.bySemanticsLabel('불러오는 중'), findsOneWidget);

    await switchTo(FixtureMode.error);
    expect(find.text('불러오지 못했어요'), findsOneWidget);
    expect(find.text('마지막 정상 수집 10월 19일 05:12'), findsOneWidget);
    expect(find.text('인터넷 연결을 확인해 주세요'), findsNothing);

    await switchTo(FixtureMode.offline);
    expect(find.text('인터넷 연결을 확인해 주세요'), findsOneWidget);

    await switchTo(FixtureMode.delayed);
    expect(find.textContaining(keepAll('모으는'), findRichText: true), findsWidgets);
    expect(find.textContaining(keepAll('05:09.')), findsOneWidget); // 마지막 정상 수집 10월 18일 05:09 (KST)

    await switchTo(FixtureMode.empty);
    expect(find.text(keepAll('최근 논문')), findsOneWidget);
    expect(find.text('10월 18일 주요 논문'), findsOneWidget); // P4: 가장 최근 다이제스트로 대신

    // 「다시 시도」는 다시 부른다(아직 error 모드라 또 실패). 정상으로 돌리면 복구된다.
    await switchTo(FixtureMode.error);
    await tester.runAsync(() async {
      await tester.tap(find.text('다시 시도'));
      await tester.pump();
    });
    expect(find.text('불러오지 못했어요'), findsOneWidget);
    await switchTo(FixtureMode.normal);
    await tester.pumpAndSettle();
    expect(find.text(keepAll('6편이 올라왔어요')), findsOneWidget);
  });

  testWidgets('M3: 오프라인에서 보관함 → S02는 제목 블록 + 오류 카드(7.7)', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    toggleBookmark('0000.00003', '보상 모델 없이 선호를 학습하는 정책 최적화');
    fixtureMode.value = FixtureMode.offline;

    router.go('/library');
    await tester.pumpAndSettle();
    expect(find.text('이 기기에 저장한 항목 1개'), findsOneWidget); // 보관함은 네트워크 없이 동작

    await tester.tap(find.text(keepAll('보상 모델 없이 선호를 학습하는 정책 최적화')));
    await settle(tester);
    expect(find.text(keepAll('보상 모델 없이 선호를 학습하는 정책 최적화')), findsOneWidget);
    expect(find.text('인터넷 연결을 확인해 주세요'), findsOneWidget);
    expect(find.text('번역과 함께 초록 읽기'), findsNothing);
  });

  testWidgets('M3: 해설 준비 중(pending) 논문은 준비 중 카드', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    router.push('/paper/0000.00006');
    await settle(tester);
    expect(find.text('해설을 준비하고 있어요'), findsOneWidget);
    expect(find.text('AI 요약'), findsNothing);
  });

  test('브리핑: 24시간 안 소식에서 주요 소식 5개(큰 연구소·모델 출시·관련 글 우선), 적으면 3일, 없으면 최근 소식', () {
    final now = DateTime.utc(2026, 10, 29, 23); // KST 10월 30일 08시
    OfficialNews n(String id, String source, String kind, String title, int hoursAgo, {List<String> related = const []}) => OfficialNews.fromJson({
      'id': id, 'source': source, 'source_label': source, 'kind': kind, 'title_en': title, 'url': 'https://e.com/$id',
      'published_at': now.subtract(Duration(hours: hoursAgo)).toIso8601String(), 'related': related,
    });
    final news = [
      n('blog', 'huggingface', 'post', 'Profiling on Trainium', 2),
      n('sdk', 'openai_sdk', 'release', 'OpenAI Python SDK v3.41.0', 3),
      n('gemini', 'deepmind', 'post', 'Gemini 4 Carbon: our next frontier model', 20, related: ['x']),
      n('spec', 'openai', 'post', 'An updated Model Spec', 6),
      n('meta', 'meta', 'post', 'Catching bugs before they ship', 7),
      n('ibm', 'ibm', 'post', 'Granite Switch 4.1.1', 10),
      n('old', 'anthropic', 'post', 'Introducing Claude 5', 60),
    ];
    final b = Briefing(news, now);
    expect(b.wide, isFalse);
    expect(b.total, 6); // 「새 소식」 숫자는 24시간 기준(60시간 전 글은 세지 않는다)
    expect(b.stories.first.id, 'gemini'); // 큰 연구소 + 모델 출시 + 관련 글
    expect(b.stories.length, 5);
    expect(b.stories.map((x) => x.id), contains('old')); // 주요 소식은 3일 안에서: 어제·그제 큰 발표도 남는다
    expect(b.rest.length, 2); // 새 소식 6건 중 주요 소식에 안 든 것
    expect(b.updates, 1);
    final quiet = Briefing([news.last], now);
    expect((quiet.wide, quiet.total, quiet.stories.length), (true, 1, 1)); // 3일 안
    final stale = Briefing([n('older', 'openai', 'post', 'x', 200)], now);
    expect((stale.stale, stale.total, stale.stories.length), (true, 0, 1)); // 새 소식 0건이어도 최근 소식은 보인다
    expect(relativeKo(now.subtract(const Duration(minutes: 5)), now), '5분 전');
    expect(relativeKo(now.subtract(const Duration(hours: 6)), now), '6시간 전');
    expect(relativeKo(DateTime.utc(2026, 10, 29, 3), now), '20시간 전'); // 24시간 안은 날짜가 바뀌었어도 시간
    expect(relativeKo(DateTime.utc(2026, 10, 28, 17), now), '1일 전'); // KST 10월 29일 02시
    expect(relativeKo(DateTime.utc(2026, 10, 26, 3), now), '4일 전');
    expect(relativeKo(DateTime.utc(2026, 9, 20, 3), now), '9월 20일'); // 한 달이 넘으면 날짜
    expect(dayHeaderKo(now.subtract(const Duration(hours: 1)), now), '오늘 · 10월 30일');
    expect(briefingLabel(now), '아침 브리핑');
    expect([newsGroup('claude_api'), newsGroup('nvidia_dev'), newsGroup('ai2')], ['Anthropic', 'NVIDIA', '기타']);
  });

  test('브리핑 화제: 크게 화제가 된 글(HN 500점·모델 출시)은 주요 소식에, 나머지 HN 글은 개발자 화제로', () {
    final now = DateTime.utc(2026, 10, 29, 23);
    OfficialNews n(String id, String source, String kind, String title, int hoursAgo, {int? points}) => OfficialNews.fromJson({
      'id': id, 'source': source, 'source_label': source, 'kind': kind, 'title_en': title, 'url': 'https://e.com/$id',
      'published_at': now.subtract(Duration(hours: hoursAgo)).toIso8601String(), 'points': points,
    });
    final b = Briefing([
      n('spec', 'openai', 'post', 'An updated Model Spec', 6),
      n('mistral', 'hn', 'hot', "We're releasing the weights of Mistral Large 4", 12, points: 1314),
      n('voice', 'hn', 'hot', 'LLM Voice', 9, points: 408),
      n('tool', 'github', 'hot', 'tool: an agent tool', 30, points: 179),
    ], now);
    expect(b.stories.first.id, 'mistral'); // 공식 출처가 없는 발표도 화제 덕에 1위
    expect(b.talk.map((x) => x.id), ['voice']); // HN 글만
    expect(b.repos.map((x) => x.id), ['tool']); // GitHub 새 저장소는 따로(별 순)
    expect(b.hotCount, 3);
    expect(b.total, 3); // 공식 1 + 24시간 안 화제 2
    expect(b.stories.first.reaction, '추천 1,314');
    expect(OfficialNews.fromJson({'id': 'g', 'source': 'deepmind', 'source_label': 'Google DeepMind', 'kind': 'post', 'title_en': 'x',
      'url': 'u', 'published_at': '2026-10-29T00:00:00Z', 'points': 331}).reaction, 'HN 추천 331'); // 공식 소식에 붙은 반응
  });

  testWidgets('소식 · HOT: 맨 위 오늘 뜨는 저장소 줄 → GitHub 칸, 아래는 「전체 | Hacker News | X」 반응 순, 상세는 원문·HN 토론 링크', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    clock = () => DateTime.utc(2026, 10, 18, 20);
    router.go('/explore');
    await settle(tester);
    await tester.tap(find.text('소식'));
    await slide(tester);
    await settle(tester);
    await tester.tap(find.descendant(of: find.byType(ExploreSectionTabs), matching: find.text('HOT')));
    await settle(tester); // 카드 줄이 GitHub 순위 fixture를 읽는다
    // GitHub는 칩이 아니라 맨 위 카드 줄. 칩은 Hacker News와 X
    Finder filter(String label) => find.descendant(of: find.byType(ExploreTextFilters), matching: find.text(label));
    expect(filter('GitHub'), findsNothing);
    expect(filter('Hacker News'), findsOneWidget);
    expect(filter('X'), findsOneWidget);
    // X 글: 번역이 있으면 한국어 위·원문 아래(「AI 번역」), 없으면 원문. 발표 소식을 단 글(9001)은 HOT에 넣지 않는다
    expect(find.text(keepAll('모든 유료 요금제의 주간 사용량 한도를 초기화했어요. 이번 주는 넉넉하게 써 보세요.')), findsOneWidget);
    expect(find.text("We've reset weekly usage limits for all paid plans. Enjoy the extra room this week, on us."), findsOneWidget);
    expect(find.text(keepAll('Spotted: Example Assistant is testing a new memory panel in its web app. Not live for everyone yet.')), findsOneWidget);
    expect(find.text(keepAll('가장 새로운 예시 모델을 소개해요. 자세히 보기: https://t.co/x')), findsNothing);
    expect(find.text('@ExampleLab · 10시간 전'), findsOneWidget); // 작성자·@핸들·시각을 늘 같이
    await tester.tap(filter('Hacker News'));
    await tester.pumpAndSettle();
    expect(find.byType(XPostCard), findsNothing);
    await tester.tap(filter('X'));
    await tester.pumpAndSettle();
    expect(find.byType(XPostCard), findsNWidgets(2));
    expect(find.text(keepAll('LLM 글쓰기 문체에 관한 가상 글')), findsNothing);
    double yx(String id) => tester.getTopLeft(find.byWidgetPredicate((w) => w is XPostCard && w.post.id == id)).dy;
    expect(yx('9002'), lessThan(yx('9003'))); // 좋아요 순(2,400 > 650)
    await tester.tap(filter('전체'));
    await tester.pumpAndSettle();
    expect(find.text('오늘 뜨는 저장소'), findsOneWidget);
    expect(find.text(keepAll('10월 18일 15:17 ~ 10월 19일 15:17 사이에 생긴 저장소')), findsOneWidget); // 기간을 그대로 적는다
    expect(find.text('day-tool-1'), findsOneWidget);
    for (final title in ['Example-4 가중치 공개', 'LLM 글쓰기 문체에 관한 가상 글']) {
      expect(find.text(keepAll(title)), findsOneWidget);
    }
    expect(find.text(keepAll('example-tool: 가상의 에이전트 도구')), findsNothing); // 저장소는 GitHub 칸 순위로
    double y(String t) => tester.getTopLeft(find.text(keepAll(t))).dy;
    expect(y('Example-4 가중치 공개'), lessThan(y('LLM 글쓰기 문체에 관한 가상 글'))); // 점수 순
    Finder stat(String label) => find.byWidgetPredicate((w) => w is HomeStat && w.label == label);
    expect(stat('Example AI 추천 1,314'), findsOneWidget);
    expect(stat('댓글 360'), findsOneWidget);
    expect(find.text('추천'), findsNothing);
    await tester.tap(find.text(keepAll('LLM 글쓰기 문체에 관한 가상 글')));
    await settle(tester);
    expect(find.text('Hacker News 토론'), findsOneWidget);
    expect(find.text('댓글 213'), findsOneWidget);
    router.pop();
    await settle(tester);
    // 「전체 순위」 → GitHub 칸 일간
    await tester.tap(find.text('전체 순위'));
    await slide(tester);
    await settle(tester);
    expect((exploreTab.value, githubPeriod.value), (3, 0));
    clock = DateTime.now;
  });

  testWidgets('X: 발표 카드에 같은 소식을 단 X 글의 반응, 홈 맨 위 혜택·한도 소식', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    clock = () => DateTime.utc(2026, 10, 18, 20);
    await pumpApp(tester);
    clock = () => DateTime.utc(2026, 10, 18, 20);
    resetXPerks();
    router.go('/home');
    await settle(tester);
    expect(find.text(keepAll('혜택·한도 소식')), findsOneWidget);
    expect(find.byType(XPostCard), findsOneWidget); // 혜택 글 하나(9002)만
    expect(find.text(keepAll('모든 유료 요금제의 주간 사용량 한도를 초기화했어요. 이번 주는 넉넉하게 써 보세요.')), findsOneWidget);
    router.go('/explore');
    await settle(tester);
    await tester.tap(find.text('소식'));
    await slide(tester);
    await settle(tester);
    await openDates(tester);
    expect(find.byType(XReactionLine), findsOneWidget); // fixture anthropic-1 소식을 단 X 글
    expect(find.text('X 좋아요 5,200 · @ExampleLab'), findsOneWidget);
    clock = DateTime.now;
  });

  testWidgets('GitHub 칸: 「일간 | 주간 | 월간」, 기간 시작·끝과 모은 시각, 별 많은 순 순위', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    clock = () => DateTime.utc(2026, 10, 18, 20);
    router.go('/explore');
    await settle(tester);
    await tester.tap(find.text('GitHub'));
    await slide(tester);
    await settle(tester);
    Finder tab(String l) => find.descendant(of: find.byType(ExploreSectionTabs), matching: find.text(l));
    expect(tab('일간'), findsOneWidget);
    expect(find.text(keepAll('10월 18일 15:17 ~ 10월 19일 15:17')), findsOneWidget);
    expect(find.textContaining(keepAll('별 수는 10월 19일 15:17에 모은 값이에요.')), findsOneWidget);
    expect(find.text('day-tool-1'), findsOneWidget);
    await tester.tap(tab('주간'));
    await tester.pumpAndSettle();
    expect(githubPeriod.value, 1);
    expect(find.text(keepAll('10월 12일 15:17 ~ 10월 19일 15:17')), findsOneWidget);
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(y('week-tool-1'), lessThan(y('week-tool-2'))); // 별 많은 순
    expect(find.text('day-tool-1'), findsNothing);
    // 설명이 아직 옮겨지지 않은 저장소는 원문 설명
    expect(find.text(keepAll('An open-source agent toolkit #4 for running LLM workflows locally')), findsOneWidget);
    await tester.tap(tab('월간'));
    await tester.pumpAndSettle();
    expect(find.text(keepAll('9월 19일 15:17 ~ 10월 19일 15:17')), findsOneWidget);
    expect(tester.takeException(), isNull);
    clock = DateTime.now;
  });

  testWidgets('공식 소식(발표): 회사 묶음 필터, 날짜 머리, 지난번 본 곳에 「여기까지 봤어요」 선', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    newsSeenAt.value = DateTime.utc(2026, 10, 17, 12); // 지난번엔 10월 17일 낮 글까지 봤다
    router.go('/explore');
    await settle(tester);
    await tester.tap(find.text('소식'));
    await slide(tester);
    await settle(tester);
    await openDates(tester);
    expect(find.text('지난번에 여기까지 봤어요'), findsOneWidget);
    expect(find.descendant(of: find.byType(ExploreTextFilters), matching: find.text('OpenAI')), findsOneWidget);
    expect(find.descendant(of: find.byType(ExploreTextFilters), matching: find.text('OpenAI 커뮤니티')), findsNothing); // 같은 회사는 한 필터
    await tester.pump(const Duration(milliseconds: 50));
    expect(newsSeenAt.value!.isAfter(DateTime.utc(2026, 10, 17, 12)), isTrue); // 이번 맨 위 글로 옮겨 둔다
  });

  test('S02 요약 문단 나누기: 한국어 문장 끝에서만', () {
    expect(
      summaryParagraphs('첫 문장이다. Exact Match를 3.0배 높인다(예: GPT). 마지막이에요! '),
      ['첫 문장이다.', 'Exact Match를 3.0배 높인다(예: GPT).', '마지막이에요!'],
    );
    expect(summaryParagraphs(''), isEmpty);
  });

  testWidgets('S01: 추천 카드 불릿은 항목당 2줄까지', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    // 홈은 불릿 대신 첫 핵심 내용을 두 줄 요약으로(피드백 6번), 불릿은 탐색 논문 칸의 추천 카드에
    expect(tester.widget<Text>(find.text(keepAll('입력 복잡도에 따른 추론 연산의 동적 배분'))).maxLines, 2);
    router.go('/explore');
    await settle(tester);
    final bullet = tester.widget<Text>(find.text(keepAll('입력 복잡도에 따른 추론 연산의 동적 배분')));
    expect(bullet.maxLines, 2);
    expect(bullet.overflow, TextOverflow.ellipsis);
  });

  test('M5: Supabase 읽기 함수 호출(공식 소식·모델 포함), 응답 캐시, 실패 시 캐시·오프라인 오류', () async {
    final calls = <String>[];
    var online = true;
    final client = MockClient((req) async {
      calls.add('${req.url.path} ${req.body}');
      expect(req.headers['apikey'], 'pk');
      if (!online) throw http.ClientException('no network');
      final body = switch (req.url.pathSegments.last) {
        'list_digests' => {'digests': [{'digest_date': '2026-10-22', 'source_date': '2026-10-21', 'status': 'published', 'paper_count': 1, 'primary_topic': 'agent', 'last_success_at': '2026-10-21T20:12:00Z'}], 'next_cursor': null},
        'get_digest' => {'digest_date': '2026-10-22', 'status': 'published', 'last_success_at': '2026-10-21T20:12:00Z', 'featured_paper_id': null, 'papers': []},
        'list_official_news' => {'items': [{'id': 'abc', 'source': 'openai', 'source_label': 'OpenAI', 'kind': 'post', 'category': null, 'title_en': 'T', 'title_ko': '제목', 'url': 'https://e.com/a', 'published_at': '2026-10-26T00:00:00Z', 'summary_ko': '요약', 'key_points': []}]},
        'list_trending_models' => {'models': [{'id': 'a/b', 'rank': 1, 'author': 'a', 'name': 'b', 'task': 'text-generation', 'params': null, 'license': 'mit', 'likes': 1, 'downloads': 2, 'created_at': null, 'arxiv': null, 'url': 'https://huggingface.co/a/b', 'card': null}]},
        _ => null,
      };
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
    });
    // .env에 /rest/v1/까지 넣어도 받아 준다
    final repo = SupabaseRepository('https://x.supabase.co/rest/v1/', 'pk', client: client);

    // 날짜 목록을 받기 전이라도 다이제스트 저장본에서 마지막 정상 수집 시각을 찾는다
    final fresh = SupabaseRepository('https://x.supabase.co', 'pk', client: client);
    (await SharedPreferences.getInstance()).remove('cache.digests');
    expect((await fresh.getDigest('2026-10-22'))!.status, 'published');
    online = false;
    await expectLater(fresh.getPaper('nope'),
        throwsA(isA<LoadError>().having((e) => e.lastSuccessAt, 'lastSuccessAt', DateTime.utc(2026, 10, 21, 20, 12))));
    online = true;
    calls.clear();

    expect((await repo.listDigests()).single.primaryTopic, 'agent');
    expect((await repo.getDigest('2026-10-22'))!.status, 'published');
    expect(calls.first, startsWith('/rest/v1/rpc/list_digests '));
    expect(calls[1], '/rest/v1/rpc/get_digest {"d":"2026-10-22"}');

    online = false;
    expect((await repo.getDigest('2026-10-22'))!.status, 'published'); // 오프라인: 저장본
    await expectLater(
      repo.getPaper('0000.00001'), // 저장본 없음 → 오프라인 오류, 마지막 정상 수집은 저장된 목록에서
      throwsA(isA<LoadError>()
          .having((e) => e.offline, 'offline', true)
          .having((e) => e.lastSuccessAt, 'lastSuccessAt', DateTime.utc(2026, 10, 21, 20, 12))),
    );

    // 공식 소식·트렌딩 모델도 읽기 함수로(미리보기 스냅샷을 넣지 않은 빌드), 오프라인이면 저장본
    online = true;
    calls.clear();
    expect((await repo.listOfficialNews()).single.titleKo, '제목');
    expect((await repo.listTrendingModels()).single.id, 'a/b');
    expect(calls, ['/rest/v1/rpc/list_official_news {"lim":400}', '/rest/v1/rpc/list_trending_models {}']);
    online = false;
    expect((await repo.listOfficialNews()).single.id, 'abc');
  });

  testWidgets('C02: 약어는 정식 명칭 한 줄, 원어와 같은 대응어는 숨김', (tester) async {
    final slam = GlossaryTerm.fromJson({
      'term': 'SLAM', 'definition_ko': '가상 정의.', 'sentence_ids': ['A01'], 'highlight': true,
      'term_ko': 'SLAM', 'full_form_en': 'Simultaneous Localization and Mapping',
    });
    final empty = GlossaryTerm.fromJson({'term': 'MTEB', 'definition_ko': '가상 정의.', 'full_form_en': ''});
    expect(empty.fullForm, isNull); // 빈 문자열 = 확인했지만 없음
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => TextButton(onPressed: () => showTermSheet(context, slam), child: const Text('열기'))),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('Simultaneous Localization and Mapping'), findsOneWidget);
    expect(find.text('SLAM'), findsOneWidget); // 원어만, 대응어 줄은 없음
  });

  testWidgets('C02: 설명 끝 「예:」는 뜻 아래 예시 상자로, 괄호 안 「예:」는 뜻 그대로', (tester) async {
    expect(splitExample('비율. 예: 10개 중 8개일 때 80%.'), ('비율.', '10개 중 8개일 때 80%.'));
    expect(splitExample('구조.\n과거에는 전용 백본(예: ResNet, ViT)이 쓰였다'), ('구조.\n과거에는 전용 백본(예: ResNet, ViT)이 쓰였다', null));
    expect(splitExample('예: 뜻 없이 예시만'), ('예: 뜻 없이 예시만', null));
    final recall = GlossaryTerm.fromJson({
      'term': 'recall', 'definition_ko': '실제 양성 중 찾아낸 비율. 예: 스팸 10개 중 8개를 찾으면 80%.', 'sentence_ids': ['A01'],
    });
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => TextButton(onPressed: () => showTermSheet(context, recall), child: const Text('열기'))),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text(keepAll('실제 양성 중 찾아낸 비율.')), findsOneWidget);
    expect(find.text('예시'), findsOneWidget);
    expect(find.text(keepAll('스팸 10개 중 8개를 찾으면 80%.')), findsOneWidget);
  });

  testWidgets('Q03: 라벨만 남긴 버튼도 화면 읽기 탭 동작이 있다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: RgCircleButton(semanticLabel: '공유', icon: 'share', onTap: () {})),
    ));
    final node = tester.getSemantics(find.bySemanticsLabel('공유'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
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
    await tester.tap(find.bySemanticsLabel('닫기').last);
    await tester.pumpAndSettle();
    expect(find.text('inference-time compute'), findsNothing);
  });

  testWidgets('기기 글자 크기: 기기에서 최대(AX5, 3.12배)·굵은 텍스트로 해도 앱 글자는 그대로', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 3.12;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(boldText: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(tester);
    router.go('/home');
    await settle(tester);
    expect(MediaQuery.textScalerOf(tester.element(find.text('홈'))).scale(1), 1.0);
    expect(MediaQuery.boldTextOf(tester.element(find.text('홈'))), isFalse);
    final title = find.text(keepAll('오늘의 논문'));
    await tester.scrollUntilVisible(title, 300, scrollable: find.byType(Scrollable).first);
    expect(MediaQuery.textScalerOf(tester.element(title)).scale(1), 1.0);
    // 앱 안 「글자 크기」는 그대로 듣는다
    router.push('/paper/0000.00001');
    await settle(tester);
    readerScale.value = 1.3;
    await tester.pump();
    await revealPaperContent(tester, find.text('핵심 내용'));
    expect(MediaQuery.textScalerOf(tester.element(find.text('핵심 내용'))).scale(1), 1.3);
    readerScale.value = 1.0;
  });

  testWidgets('화면 바탕: 홈과 같은 회청 바탕 하나, 읽기 설정에 「화면 바탕」 고르기는 없다', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    Color scaffoldBg() => Theme.of(tester.element(find.text('홈'))).scaffoldBackgroundColor;
    expect(scaffoldBg(), RgPalette.white.bgApp);
    router.go('/settings/reading');
    await settle(tester);
    expect(find.text('화면 모드'), findsOneWidget);
    expect(find.text('화면 바탕'), findsNothing);
    expect(find.text('종이'), findsNothing);
  });

  testWidgets('사용 방법: 설정에서 열고, 자주 묻는 질문 펼치기, 도움말 다시 보기, 처음 안내 5장 넘기고 돌아오기', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    router.go('/settings');
    await settle(tester);
    await tester.tap(find.text('사용 방법'));
    await settle(tester);
    expect(find.text('기능 사용법'), findsOneWidget);
    expect(find.text('자주 묻는 질문'), findsOneWidget);

    Finder keep(String text) => find.byWidgetPredicate((w) => w is KeepAllText && w.text == text);
    const answer = '아니요. 설치하면 바로 쓸 수 있고, 이름이나 이메일을 받지 않아요.';
    expect(keep(answer), findsNothing);
    await tester.tap(keep('회원가입이나 로그인이 필요한가요?'));
    await tester.pumpAndSettle();
    expect(keep(answer), findsOneWidget);

    expect(tipsSeen.value, isNotEmpty);
    await tester.tap(find.text('도움말 다시 보기'));
    await tester.pump();
    expect(tipsSeen.value, isEmpty);
    expect(find.text('읽기 화면과 소식에서 도움말이 다시 떠요'), findsOneWidget);
    tipsSeen.value = {tipReader, tipNews};

    onboardingDone.value = false;
    addTearDown(() => onboardingDone.value = true);
    await tester.tap(find.text('처음 안내 다시 보기'));
    await settle(tester);
    expect(find.text('건너뛰기'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
    }
    expect(find.text('시작하기'), findsOneWidget);
    await tester.tap(find.text('시작하기'));
    await settle(tester);
    expect(onboardingDone.value, isTrue);
    expect(find.text('기능 사용법'), findsOneWidget); // 다시 보기로 열었으면 닫히고 사용 방법으로
  });

  testWidgets('화면 모드: 「어둡게」면 바탕과 무관하게 어두운 색, 「기기 설정」은 기기 다크 모드를 따른다', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() {
      appearance.value = Appearance.system;
      platformDark.value = false;
    });
    await pumpApp(tester);
    Color scaffoldBg() => Theme.of(tester.element(find.text('홈'))).scaffoldBackgroundColor;

    router.go('/settings/reading');
    await settle(tester);
    await tester.tap(find.text('어둡게'));
    await tester.pump();
    // 한 프레임에 확 바뀌지 않게: 직전 화면이 위에 덮였다가 흐려지며 사라진다(RgMotion.base)
    expect(find.byType(RawImage), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsNothing);
    expect(scaffoldBg(), RgPalette.dark.bgApp);
    expect(RgText.titleList.color, RgInk.dark.textPrimary); // 글자 스타일도 다시 읽힌다
    expect((await SharedPreferences.getInstance()).getString('settings.appearance'), 'dark');
    // 어두운 화면에서도 화면마다 깨지지 않는다
    for (final path in ['/home', '/explore', '/library', '/settings']) {
      router.go(path);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: path);
    }

    appearance.value = Appearance.system;
    await tester.pumpAndSettle();
    expect(scaffoldBg(), RgPalette.white.bgApp);
    platformDark.value = true; // 기기를 다크로
    await tester.pumpAndSettle();
    expect(scaffoldBg(), RgPalette.dark.bgApp);

    // 「동작 줄이기」면 전환 없이 바로
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    platformDark.value = false;
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);
    expect(scaffoldBg(), RgPalette.white.bgApp);
  });

  testWidgets('옆으로 밀기: 홈 → 탐색 칸들 → 공식 소식 발표·업데이트 → 모델 트렌딩·새로 나옴 → GitHub 일간·주간·월간 → 보관함 → 설정, 반대로 밀면 거꾸로', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    String where() {
      final path = router.routerDelegate.currentConfiguration.uri.path;
      final sub = switch (exploreTab.value) {
        1 => const [' 발표', ' 업데이트', ' 화제'][newsTab.value],
        2 => modelsFresh.value ? ' 새로 나옴' : ' 트렌딩',
        3 => const [' 일간', ' 주간', ' 월간'][githubPeriod.value],
        _ => '',
      };
      return path == '/explore' ? 'explore ${exploreTab.value}$sub' : path;
    }


    Future<void> swipe(double dx) async {
      await tester.flingFrom(const Offset(200, 700), Offset(dx, 0), 1200);
      await slide(tester); // 칸 넘김 애니메이션
      await settle(tester);
    }

    const forward = ['explore 0', 'explore 1 발표', 'explore 1 업데이트', 'explore 1 화제', 'explore 2 트렌딩', 'explore 2 새로 나옴',
      'explore 3 일간', 'explore 3 주간', 'explore 3 월간', '/library', '/settings'];
    for (final w in forward) {
      await swipe(-300);
      expect(where(), w);
    }
    await swipe(-300); // 설정이 끝: 더 가지 않는다
    expect(where(), '/settings');
    for (final w in forward.reversed.skip(1)) {
      await swipe(300);
      expect(where(), w);
    }
    await swipe(300);
    expect(where(), '/home');
    // 짧게 살짝 끈 것은 넘기지 않는다
    await tester.dragFrom(const Offset(200, 700), const Offset(-20, 0));
    await settle(tester);
    expect(where(), '/home');

    // 탭 안 하위 화면(지난 날짜)에서는 넘기지 않는다(가장자리 뒤로 가기와 다투지 않게)
    router.go('/explore/2026-10-18');
    await settle(tester);
    await swipe(-300);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/explore/2026-10-18');
    expect(tester.takeException(), isNull);
  });

  testWidgets('마이크로인터랙션: 북마크·탭·칸 진동, 밑줄은 고른 칸 아래에 표시된다', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpApp(tester);

    // 북마크: 가벼운 톡, 저장되면 원이 톡 튀었다 돌아온다
    await tester.tap(find.bySemanticsLabel('북마크에 저장').first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    expect(find.byWidgetPredicate((w) => w is ScaleTransition && w.scale.value != 1), findsOneWidget);
    await tester.pumpAndSettle();

    // 탭바: 다른 칸을 누르면 선택 틱, 지금 칸을 다시 누르면 없음
    haptics.clear();
    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();
    expect(haptics, isEmpty);
    await tester.tap(find.text('탐색'));
    await settle(tester);
    expect(haptics, ['HapticFeedbackType.selectionClick']);

    // 공식 소식 안 밑줄 탭: 선택 틱, 밑줄이 「업데이트」 아래로
    await tester.tap(find.text('소식'));
    await slide(tester);
    await settle(tester);
    haptics.clear();
    final newsTabs = find.ancestor(of: find.text('발표'), matching: find.byType(ExploreSectionTabs)).first;
    final underline = find.descendant(
      of: newsTabs,
      matching: find.byWidgetPredicate((w) => w is ColoredBox && w.color == RgColors.textPrimary),
    );
    expect(underline, findsOneWidget);
    final before = tester.getCenter(underline).dx;
    expect(before, closeTo(tester.getCenter(find.text('발표')).dx, 1));
    expect(tester.getSemantics(find.text('발표')), isSemantics(isSelected: true));
    await tester.tap(find.text('업데이트'));
    await tester.pump();
    await tester.pump(); // 새 선택 폭을 측정한 다음 이동한다
    await tester.pump(const Duration(milliseconds: 60));
    final during = tester.getCenter(underline).dx;
    expect(during, greaterThan(before));
    expect(during, lessThan(tester.getCenter(find.text('업데이트')).dx));
    await tester.pumpAndSettle();
    expect(haptics, ['HapticFeedbackType.selectionClick']);
    expect(tester.getCenter(underline).dx, closeTo(tester.getCenter(find.text('업데이트')).dx, 1));
    expect(tester.getSemantics(find.text('업데이트')), isSemantics(isSelected: true));
  });

  testWidgets('출처 칩: 회사마다 연한 면 + 같은 색 계열 진한 글자(같은 회사는 같은 색)', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    // 탐색은 중립 메타 행이고, 홈 소식 카드가 회사 색 칩을 사용한다.
    final colors = <String, Color?>{}, text = <String, Color?>{};
    for (final e in find.descendant(of: find.byType(HomeStoryRow), matching: find.byType(HomeChip)).evaluate()) {
      final chip = e.widget as HomeChip;
      colors[chip.label] = chip.background;
      text[chip.label] = chip.foreground;
    }
    expect(colors['Anthropic'], RgBrand.anthropic.background);
    expect(colors['OpenAI'], RgBrand.openai.background);
    expect(colors['Google DeepMind'], RgBrand.google.background);
    // 글자는 순검정·흰색 대신 면과 같은 색 계열의 진한 색(피드백 1번)
    expect(text['Anthropic'], RgBrand.anthropic.foreground);
    expect(text['OpenAI'], RgBrand.openai.foreground);
    expect(text['Google DeepMind'], RgBrand.google.foreground);
    expect(brandOf('Google Research'), (RgBrand.google.background, RgBrand.google.foreground)); // Google은 파랑 하나
    expect(brandOf('Hugging Face'), (RgBrand.huggingface.background, RgBrand.huggingface.foreground));
  });

  testWidgets('대표 카드: 홈·탐색 모두 어두운 카드(흰 글자), 탐색 논문 목록은 제목·저자·날짜', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    Color face() => (tester.widget<Container>(find.descendant(of: find.byType(HomeFeaturedPaper).first, matching: find.byType(Container)).first)
            .decoration as BoxDecoration)
        .color!;
    expect(face(), RgHome.paperCard);
    router.go('/explore');
    await settle(tester);
    expect(face(), RgHome.paperCard); // 탐색도 홈 카드 기준(2026-11-01)
    final digest = await tester.runAsync(repository.today);
    final papers = HomeView(digest!.papers, null).list;
    expect(papers, hasLength(5)); // 대표 논문은 목록에서 빠진다.
    for (final paper in papers) {
      expect(find.text(keepAll(paper.title)), findsOneWidget);
      final date = DateTime.parse(paper.publishedAt);
      final authors = paper.authorCount > 1 ? '${paper.firstAuthor} 외 ${paper.authorCount - 1}명' : paper.firstAuthor;
      expect(find.text('$authors · ${date.month}월 ${date.day}일'), findsOneWidget);
    }
  });

  testWidgets('논문 상세 카드: AI 요약·핵심 내용에도 용어 강조, 카드 안에서 용어당 처음 1번, 누르면 진동과 시트', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add('${call.arguments}');
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpApp(tester);
    router.push('/paper/0000.00001');
    await settle(tester);
    await revealPaperContent(tester, find.bySemanticsLabel('용어 설명: compute budget'));
    // 요약에 「연산 예산」(번역문 표기)·「벤치마크」, 핵심 내용 2번에도 「연산 예산」이 있지만 카드 안에서는 1번만
    expect(find.bySemanticsLabel('용어 설명: compute budget'), findsOneWidget);
    expect(find.bySemanticsLabel('용어 설명: Benchmark'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('용어 설명: compute budget'));
    await tester.pumpAndSettle();
    expect(haptics, ['HapticFeedbackType.selectionClick']);
    expect(find.text('이 논문에서의 뜻'), findsOneWidget);
    expect(find.text('연산 예산'), findsWidgets); // 사전 대응어가 없으면 번역문 표기를 제목 아래에
  });

  test('용어 찾기: 영문은 낱말 단위, 한글은 앞이 한글이 아닐 때만(뒤에는 조사가 붙는다)', () {
    expect(findTerm('RAGAS와 RAG를 쓴다', 'RAG'), 'RAGAS와 '.length);
    expect(findTerm('VLMs are', 'VLM'), -1);
    expect(findTerm('공간 VLM이', 'VLM'), '공간 '.length);
    expect(findTerm('에이전트용 모델', '에이전트'), 0);
    expect(findTerm('멀티에이전트 구조', '에이전트'), -1);
  });

  testWidgets('모델: 「트렌딩 | New」, 변형 묶음 펼치기, 처음 보는 모델은 「새로 진입」', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    clock = () => DateTime.utc(2026, 10, 29);
    modelsSeen.value = {'example-lab/example-coder': 'base', 'example-lab/example-video': 'base'};
    router.go('/explore');
    await settle(tester);
    await tester.tap(find.text('모델'));
    await slide(tester);
    await settle(tester);
    // 트렌딩: 10위 안만(example-tiny는 11위라 없다). 1위 변형은 한 줄로 묶인다
    expect(find.text('example-coder'), findsOneWidget);
    expect(find.text('example-tiny'), findsNothing);
    expect(find.text('변형 1개 · GGUF'), findsOneWidget);
    expect(find.text(keepAll('example-coder-GGUF · example-quant · 양자화판')), findsNothing);
    await tester.tap(find.bySemanticsLabel('변형 1개'));
    await tester.pumpAndSettle();
    expect(find.text(keepAll('example-coder-GGUF · example-quant · 양자화판')), findsOneWidget);

    // 새로 나옴: 최근 14일 안에 공개된 모델만, 공개일이 머리 줄에. 처음 보는 모델은 「새로 진입」
    await tester.tap(find.descendant(of: find.byType(ExploreSectionTabs), matching: find.text('New')));
    await tester.pumpAndSettle();
    expect(modelsFresh.value, isTrue);
    expect(find.text('example-tiny'), findsOneWidget);
    expect(find.text('example-video'), findsNothing);
    expect(find.text('example-coder'), findsNothing); // 10월 15일 공개 → 14일 지남
    expect(find.text('example-lab · 17억 파라미터 텍스트 생성 모델'), findsOneWidget);
    expect(find.text('10월 27일'), findsOneWidget); // 공개일은 한국 날짜로 표시한다.
    final entered = find.byWidgetPredicate((w) => w is RgNewLabel && w.visible && w.label == '새로 진입');
    expect(entered, findsOneWidget); // 글자 대신 점, 화면 읽기에는 「새로 진입」
    await tester.tap(find.text('example-tiny'));
    await settle(tester);
    expect(find.text(keepAll('Hugging Face 최근 공개')), findsOneWidget); // 트렌딩 10위 밖
    router.pop();
    await settle(tester);
    expect(entered, findsNothing); // 열어 봤으니 뗀다
    clock = DateTime.now;
  });

  testWidgets('S1: 글자 크기 4단계가 S02 AI 요약·핵심 내용에도 적용된다', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    router.push('/paper/0000.00001');
    await settle(tester);

    double scaleOf(String text) => MediaQuery.textScalerOf(tester.element(find.text(text))).scale(1);
    expect(scaleOf('Efficient Scaling of Inference-Time Compute'), 1.0); // 제목 블록은 본문 배율과 별개
    await revealPaperContent(tester, find.text('핵심 내용'));
    expect(scaleOf('핵심 내용'), 1.0);
    readerScale.value = 1.3;
    await tester.pump();
    expect(scaleOf('핵심 내용'), 1.3);
    expect(scaleOf('AI 요약'), 1.3);
    expect(scaleOf('Efficient Scaling of Inference-Time Compute'), 1.0);

    // 상세 dock에서 초록 리더를 열고 「가」의 실제 4단계 시트에서 고른다.
    await tester.tap(find.text('번역과 함께 초록 읽기'));
    await settle(tester);
    expect(find.byType(ReaderScreen), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('글자 크기'));
    await tester.pumpAndSettle();
    for (final (_, label) in readerScales) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('작게'));
    await tester.pumpAndSettle();
    expect(readerScale.value, 0.9);
    await tester.tap(find.bySemanticsLabel('닫기'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('뒤로'));
    await settle(tester);
    expect(find.byType(PaperScreen), findsOneWidget);
    await revealPaperContent(tester, find.text('핵심 내용'));
    expect(scaleOf('핵심 내용'), 0.9);
    expect(scaleOf('AI 요약'), 0.9);
  });

  testWidgets('Q02: 더 큰 텍스트에서 세그먼트·칩이 글자 높이만큼 늘고, S03 상단 바 안에 들어간다', (tester) async {
    const line = 14 * 1.2; // bodySmall, 줄 높이 1.2
    for (final scale in [1.0, 1.5, 3.0]) {
      // S03 상단 바처럼 52 고정 높이 안에 세그먼트, 그 아래 칩
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: const Size(390, 844), textScaler: TextScaler.linear(scale)),
          child: Column(children: [
            SizedBox(
              height: RgSpace.topBar,
              child: Row(children: [
                Expanded(child: RgSegmented(options: readerScales, value: 1.0, onChanged: (_) {})),
              ]),
            ),
            RgFilterChip(label: '언어 모델', selected: false, onTap: () {}),
          ]),
        ),
      ));
      expect(tester.takeException(), isNull, reason: '$scale배');

      final shown = line * (scale > 2 ? 2 : scale); // 2배에서 멈춘다
      final seg = tester.getSize(find.byType(RgSegmented<double>)).height;
      final chip = tester.getSize(find.byType(RgFilterChip)).height;
      if (scale == 1.0) {
        expect((seg, chip), (46.0, RgSpace.minTouch)); // 기본 크기는 시안 그대로(리디자인 세그먼트 46)
      } else {
        expect(seg, greaterThanOrEqualTo(shown + 2 * RgSpace.s4));
        expect(seg, lessThanOrEqualTo(RgSpace.topBar));
        expect(chip, greaterThanOrEqualTo(shown + RgSpace.s16));
      }
    }
  });
}
