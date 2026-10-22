import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:rootgist/app_shell.dart';
import 'package:rootgist/data/models.dart';
import 'package:rootgist/data/repository.dart';
import 'package:rootgist/data/settings.dart';
import 'package:rootgist/data/supabase_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rootgist/data/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rootgist/features/settings/ai_notice_sheet.dart';
import 'package:rootgist/features/settings/settings_screen.dart';
import 'package:rootgist/debug/widget_gallery.dart';
import 'package:rootgist/design/typography.dart';
import 'package:rootgist/features/explore/explore_screen.dart';
import 'package:rootgist/features/home/home_screen.dart';
import 'package:rootgist/features/paper/paper_screen.dart';
import 'package:rootgist/features/reader/reader_screen.dart';
import 'package:rootgist/main.dart';

// 에셋 읽기는 실제 I/O라 fake async 안에서 시작하면 끝나지 않고, rootBundle이 그 미완료 Future를 캐시해
// 다음 테스트까지 막는다. 첫 프레임(initState의 fixture 읽기)을 실제 async 영역에서 띄운다.
Future<void> pumpApp(WidgetTester tester) async {
  router.go('/home'); // 전역 라우터·북마크라 이전 테스트 상태가 남는다
  bookmarks.value = {};
  readerDefaultMode.value = ReaderMode.together;
  readerScale.value = 1.0;
  fixtureMode.value = FixtureMode.normal;
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
  // 앱 시작과 같이 저장값을 한 번 읽고, 이후 변경을 저장하는 리스너를 단다.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'bookmarks': jsonEncode([Bookmark('0000.00002', '저장된 논문', DateTime(2026, 10, 15)).toJson()]),
      'settings.readerMode': 'original',
      'settings.readerScale': 1.15,
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
    expect(bookmarks.value.keys, ['0000.00001']);

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

    // G2: 한국어 대응어가 있는 용어만 번역문에서 찾는다
    final ko = firstHighlights(p, korean: true);
    expect(ko.keys, ['A01']);
    expect(ko['A01']!.single.$3, '추론 시점 연산');
    expect(ko['A01']!.single.$1, '대규모 언어 모델에서 '.length);
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

    // 함께 모드: 같은 용어가 영문·한국어 양쪽에 강조되고, 한국어 쪽을 눌러도 C02에 대응어가 나온다(G1·G2)
    expect(find.bySemanticsLabel('용어 설명: inference-time compute'), findsNWidgets(2));
    await tester.tap(find.bySemanticsLabel('용어 설명: inference-time compute').first);
    await tester.pumpAndSettle();
    expect(find.text('추론 시점 연산'), findsWidgets);
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

  testWidgets('S05: 저장 목록, 해제 → 되돌리기, 전체 비우기', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);

    restoreBookmark(Bookmark('0000.00001', '추론 시점 연산의 효율적 확장', DateTime(2026, 10, 19)));
    restoreBookmark(Bookmark('0000.00003', '보상 모델 없이 선호를 학습하는 정책 최적화', DateTime(2026, 10, 18)));
    router.go('/library');
    await tester.pumpAndSettle();
    expect(find.text('이 기기에 저장한 연구 2편'), findsOneWidget);
    expect(find.text('arXiv · 10월 19일 저장'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('저장됨, 북마크 해제').first); // 최신순 첫 행 = 10월 19일
    await tester.pumpAndSettle();
    expect(find.text('이 기기에 저장한 연구 1편'), findsOneWidget);
    await tester.tap(find.text('되돌리기'));
    await tester.pumpAndSettle();
    expect(find.text('arXiv · 10월 19일 저장'), findsOneWidget); // 저장일 그대로 복원

    await tester.tap(find.text('전체 비우기'));
    await tester.pumpAndSettle();
    expect(find.text('저장한 연구 2편을 모두 뺄까요?'), findsOneWidget);
    await tester.tap(find.text('모두 빼기'));
    await tester.pumpAndSettle();
    expect(find.text('아직 저장한 연구가 없어요'), findsOneWidget);
    expect(find.text('전체 비우기'), findsNothing);
  });

  testWidgets('S06: 기본 보기가 S03에 반영, C03·데이터 출처', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester);

    router.go('/settings');
    await tester.pumpAndSettle();
    await tester.tap(find.text('원문'));
    await tester.pumpAndSettle();
    expect(readerDefaultMode.value, ReaderMode.original);

    await tester.tap(find.text('AI 생성 안내'));
    await tester.pumpAndSettle();
    expect(find.text(keepAll(aiNoticeParagraphs.first)), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('데이터 출처'));
    await tester.pumpAndSettle();
    expect(find.text(keepAll(DataSourceScreen.paragraphs.first)), findsOneWidget);

    router.push('/paper/0000.00001/reader');
    await settle(tester);
    expect(find.text(keepAll('본 연구는 입력 복잡도에 따라 추론 연산을 동적으로 배분하는 방법을 제안한다.')), findsNothing);
    expect(find.text('We propose a method that dynamically allocates inference compute according to input complexity.'), findsOneWidget);
  });

  test('C03 문구: 본문 전체를 읽었다는 표현 금지(7.8)', () {
    for (final p in aiNoticeParagraphs) {
      expect(p.contains('본문'), isFalse, reason: p);
    }
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
    expect(find.textContaining(keepAll('없어요'), findRichText: true), findsWidgets);
    expect(find.text('5편'), findsNothing);

    // 「다시 시도」는 다시 부른다(아직 error 모드라 또 실패). 정상으로 돌리면 복구된다.
    await switchTo(FixtureMode.error);
    await tester.runAsync(() async {
      await tester.tap(find.text('다시 시도'));
      await tester.pump();
    });
    expect(find.text('불러오지 못했어요'), findsOneWidget);
    await switchTo(FixtureMode.normal);
    await tester.pumpAndSettle();
    expect(find.text('5편'), findsOneWidget);
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
    expect(find.text('이 기기에 저장한 연구 1편'), findsOneWidget); // 보관함은 네트워크 없이 동작

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
    final bullet = tester.widget<Text>(find.text(keepAll('입력 복잡도에 따른 추론 연산의 동적 배분')));
    expect(bullet.maxLines, 2);
    expect(bullet.overflow, TextOverflow.ellipsis);
  });

  test('M5: Supabase 읽기 함수 호출, 응답 캐시, 실패 시 캐시·오프라인 오류', () async {
    final calls = <String>[];
    var online = true;
    final client = MockClient((req) async {
      calls.add('${req.url.path} ${req.body}');
      expect(req.headers['apikey'], 'pk');
      if (!online) throw http.ClientException('no network');
      final body = switch (req.url.pathSegments.last) {
        'list_digests' => {'digests': [{'digest_date': '2026-10-22', 'source_date': '2026-10-21', 'status': 'published', 'paper_count': 1, 'primary_topic': 'agent', 'last_success_at': '2026-10-21T20:12:00Z'}], 'next_cursor': null},
        'get_digest' => {'digest_date': '2026-10-22', 'status': 'published', 'last_success_at': '2026-10-21T20:12:00Z', 'featured_paper_id': null, 'papers': []},
        _ => null,
      };
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
    });
    // .env에 /rest/v1/까지 넣어도 받아 준다
    final repo = SupabaseRepository('https://x.supabase.co/rest/v1/', 'pk', client: client);

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
