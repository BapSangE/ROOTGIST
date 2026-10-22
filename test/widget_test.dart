import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
