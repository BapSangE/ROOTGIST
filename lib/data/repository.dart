import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

// ponytail: fixture 하나뿐이라 인터페이스 없이 둔다. M5에서 Supabase 구현이 생기면 추상 클래스로 뽑는다.
class FixtureRepository {
  Future<Map<String, dynamic>> _load(String path) async => jsonDecode(await rootBundle.loadString('fixtures/$path'));

  Future<Digest?> today() async {
    final index = await _load('digests.json');
    final date = index['fixture_today'] as String;
    final entry = (index['digests'] as List).firstWhere((d) => d['digest_date'] == date, orElse: () => null);
    if (entry == null) return null;
    if (entry['status'] != 'published') return Digest.fromJson(entry);
    return Digest.fromJson(await _load('digests/$date.json'));
  }

  Future<PaperDetail> getPaper(String id) async => PaperDetail.fromJson(await _load('papers/$id.json'));
}

final repository = FixtureRepository();

// ponytail: 메모리 북마크. M3에서 Hive로 영속화한다.
final bookmarks = ValueNotifier<Set<String>>({});

void toggleBookmark(String id) {
  final next = {...bookmarks.value};
  if (!next.remove(id)) next.add(id);
  bookmarks.value = next;
}
