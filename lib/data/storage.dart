import '../analytics/posthog_sink.dart';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../design/tokens.dart';
import 'repository.dart';
import 'settings.dart';
import 'unread.dart';

// 로컬 저장(9.4): 앱 시작 때 읽어 notifier에 넣고, 바뀔 때마다 바로 쓴다.
// ponytail: 북마크는 JSON 한 덩어리로 shared_preferences에. 수백 편을 넘기면 Hive 등으로 옮긴다.
Future<void> initStorage() async {
  final prefs = await SharedPreferences.getInstance();

  try {
    final raw = prefs.getString('bookmarks');
    if (raw != null) {
      bookmarks.value = {
        for (final j in jsonDecode(raw) as List) Bookmark.fromJson(j).id: Bookmark.fromJson(j),
      };
    }
  } catch (_) {
    // 깨진 저장값은 버린다. 북마크가 비어 보이는 쪽이 앱이 뜨지 않는 것보다 낫다.
  }
  // 새 글 기준 시각: 첫 실행 때 정해 둔다(unread.dart)
  final since = DateTime.tryParse(prefs.getString('unread.since') ?? '');
  newSince = since ?? DateTime.now().toUtc().subtract(const Duration(days: 3));
  if (since == null) await prefs.setString('unread.since', newSince.toIso8601String());
  analyticsCollectionEnabled.value = prefs.getBool('settings.analyticsConsent.v1') ?? false;
  analyticsCollectionEnabled.addListener(() => prefs.setBool('settings.analyticsConsent.v1', analyticsCollectionEnabled.value));
  readItems.value = {...?prefs.getStringList('unread.read')};
  readerDefaultMode.value = ReaderMode.values.asNameMap()[prefs.getString('settings.readerMode')] ?? ReaderMode.together;
  backdrop.value = Backdrop.values.asNameMap()[prefs.getString('settings.backdrop')] ?? Backdrop.white;
  final scale = prefs.getDouble('settings.readerScale');
  if (readerScales.any((s) => s.$1 == scale)) readerScale.value = scale!;

  bookmarks.addListener(
      () => prefs.setString('bookmarks', jsonEncode([for (final b in bookmarks.value.values) b.toJson()])));
  readItems.addListener(() => prefs.setStringList('unread.read', readItems.value.toList()));
  readerDefaultMode.addListener(() => prefs.setString('settings.readerMode', readerDefaultMode.value.name));
  readerScale.addListener(() => prefs.setDouble('settings.readerScale', readerScale.value));
  backdrop.addListener(() => prefs.setString('settings.backdrop', backdrop.value.name));
}
