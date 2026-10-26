import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'supabase_repository.dart';

// 불러오기 실패. offline이면 「인터넷 연결을 확인해 주세요」(8.1).
class LoadError implements Exception {
  const LoadError({this.offline = false, this.lastSuccessAt});
  final bool offline;
  final DateTime? lastSuccessAt; // 「마지막 정상 수집 …」, 모르면 null
}

// M3 fixture 스위치: 8.1 상태를 실제 데이터 없이 재현한다(디버그 빌드의 설정 화면에서 바꾼다).
// empty·delayed는 오늘 다이제스트에만 적용된다.
enum FixtureMode { normal, loading, error, offline, empty, delayed }

final fixtureMode = ValueNotifier(FixtureMode.normal);

// 앱이 읽는 세 모양(HANDOFF 4.3). 화면은 이 인터페이스만 안다.
abstract class Repository {
  Future<String> todayKey(); // YYYY-MM-DD
  Future<List<Digest>> listDigests(); // ① 최신순
  Future<Digest?> getDigest([String? date]); // ② date가 없으면 오늘. 없는 날은 null
  Future<PaperDetail> getPaper(String id); // ③
  Future<List<OfficialNews>> listOfficialNews(); // P8d 공식 소식, 최신순
  Future<Digest?> today() => getDigest();
}

// 개발용 fixture(빌드에 Supabase 설정이 없을 때).
class FixtureRepository extends Repository {
  Future<Map<String, dynamic>> _load(String path) async {
    switch (fixtureMode.value) {
      case FixtureMode.loading:
        return Completer<Map<String, dynamic>>().future; // 끝나지 않는 요청
      case FixtureMode.error || FixtureMode.offline:
        throw LoadError(offline: fixtureMode.value == FixtureMode.offline, lastSuccessAt: DateTime.utc(2026, 10, 18, 20, 12));
      default:
        return jsonDecode(await rootBundle.loadString('fixtures/$path'));
    }
  }

  // fixture 전용: fixture_today를 "오늘"로 쓴다.
  @override
  Future<String> todayKey() async => (await _load('digests.json'))['fixture_today'];

  @override
  Future<List<Digest>> listDigests() async => [
        for (final d in (await _load('digests.json'))['digests']) Digest.fromJson(d),
      ];

  @override
  Future<Digest?> getDigest([String? date]) async {
    final today = await todayKey();
    date ??= today;
    if (date == today && (fixtureMode.value == FixtureMode.empty || fixtureMode.value == FixtureMode.delayed)) {
      return Digest.fromJson({
        'digest_date': date,
        'status': fixtureMode.value.name,
        'paper_count': 0,
        'last_success_at': '2026-10-17T20:09:00Z',
      });
    }
    final entry = (await listDigests()).where((d) => d.dateKey == date).firstOrNull;
    if (entry == null || entry.status != 'published') return entry;
    return Digest.fromJson(await _load('digests/$date.json'));
  }

  @override
  Future<PaperDetail> getPaper(String id) async => PaperDetail.fromJson(await _load('papers/$id.json'));

  @override
  Future<List<OfficialNews>> listOfficialNews() async => [
        for (final n in (await _load('official_news.json'))['items']) OfficialNews.fromJson(n),
      ];
}

// 빌드에 --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…(공개 키)를 주면 실제 데이터,
// 없으면 fixture. 공개 키는 레포에 넣지 않는다(권리 검토 전 실데이터, HANDOFF 0.1).
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
final Repository repository =
    _supabaseUrl.isEmpty || _supabaseKey.isEmpty ? FixtureRepository() : SupabaseRepository(_supabaseUrl, _supabaseKey);

// 9.4 저장 단위. 보관함은 이 값만으로 그린다(7.7).
class Bookmark {
  const Bookmark(this.id, this.title, this.savedAt, {this.source = 'arXiv'});
  Bookmark.fromJson(Map<String, dynamic> j)
      : id = j['paper_id'],
        title = j['title_ko'],
        savedAt = DateTime.parse(j['saved_at']),
        source = j['source'] ?? 'arXiv';
  final String id;
  final String title;
  final DateTime savedAt;
  final String source;

  Map<String, dynamic> toJson() =>
      {'paper_id': id, 'title_ko': title, 'source': source, 'saved_at': savedAt.toIso8601String()};
}

// 저장은 storage.dart(키 bookmarks).
final bookmarks = ValueNotifier<Map<String, Bookmark>>({});

void toggleBookmark(String id, String title) {
  final next = {...bookmarks.value};
  if (next.remove(id) == null) next[id] = Bookmark(id, title, DateTime.now());
  bookmarks.value = next;
}

void restoreBookmark(Bookmark b) => bookmarks.value = {...bookmarks.value, b.id: b};
