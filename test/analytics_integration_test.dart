import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rootgist/main.dart';
import 'package:rootgist/app_shell.dart';
import 'package:rootgist/data/storage.dart';
import 'package:rootgist/data/repository.dart';
import 'package:rootgist/data/models.dart';
import 'package:rootgist/analytics/posthog_sink.dart';
import 'package:rootgist/features/reader/term_sheet.dart';

// No real network: this exercises the official Dart SDK through its native boundary.
// Run with POSTHOG_* test dart-defines documented in docs/ANALYTICS.md.
void main() {
  testWidgets(
    'router branches, detail, bookmark, term sheet and opt-out reach the SDK safely',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final calls = <MethodCall>[];
      const channel = MethodChannel('posthog_flutter');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'isOptOut') return false;
        if (call.method == 'distinctId') return 'test-anonymous';
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      SharedPreferences.setMockInitialValues({
        'settings.analyticsConsent.v1': true,
      });
      await initStorage();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      router.go('/home');
      await tester.runAsync(() async {
        await tester.pumpWidget(const RootgistApp());
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pumpAndSettle();
      Future<void> go(String path, {bool push = false}) async {
        if (push) {
          router.push(path);
        } else {
          router.go(path);
        }
        await tester.runAsync(() async {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 250));
        });
        await tester.pumpAndSettle();
      }

      List<Map> events() => calls
          .where((c) => c.method == 'capture')
          .map((c) => c.arguments as Map)
          .toList();
      expect(calls.where((c) => c.method == 'setup').length, 1);
      await go('/paper/0000.00001', push: true);
      expect(events().where((e) => e['eventName'] == 'paper_opened').length, 1);
      await go('/paper/0000.00001/reader', push: true);
      router.pop();
      await tester.pumpAndSettle();
      expect(
        events().where((e) => e['eventName'] == 'reader_opened').length,
        1,
      );
      expect(events().any((e) => e['eventName'] == 'reader_active_time'), true);
      toggleBookmark('0000.00001', '이 제목은 절대로 전송하지 않음');
      await tester.pumpAndSettle();
      showTermSheet(
        tester.element(find.byType(Scaffold).last),
        GlossaryTerm.fromJson({
          'term': 'secret term text',
          'definition_ko': 'secret definition',
          'highlight': true,
        }),
      );
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      router.pop(); // detail -> home, following the real app's push stack
      await tester.pumpAndSettle();
      await go('/news/test-news-id', push: true);
      await go('/explore');
      exploreTab.value = 2;
      await tester.pumpAndSettle();
      final captured = events();
      expect(captured.where((e) => e['eventName'] == 'paper_opened').length, 2);
      expect(
        captured.where((e) => e['eventName'] == 'official_news_opened').length,
        1,
      );
      expect(captured.any((e) => e['eventName'] == 'bookmark_added'), true);
      expect(captured.any((e) => e['eventName'] == 'term_opened'), true);
      expect(captured.any((e) => e['eventName'] == 'category_selected'), true);
      expect(captured.toString(), isNot(contains('secret')));
      expect(captured.toString(), isNot(contains('제목')));
      analyticsCollectionEnabled.value = false;
      await tester.pumpAndSettle();
      final count = events().length;
      await go('/library');
      toggleBookmark('0000.00001', 'not sent');
      await tester.pumpAndSettle();
      expect(events().length, count);
      expect(calls.any((c) => c.method == 'disable'), true);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !analytics.configured,
  );
}
