import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'repository.dart';

// M5: Supabase 읽기 함수(supabase/migrations, HANDOFF 4.3)를 공개 키로 부른다.
// 받은 응답은 cache.<함수>.<인자>에 저장하고(9.4), 요청이 실패하면 저장본을 보여 준다(8.1 오프라인).
class SupabaseRepository extends Repository {
  SupabaseRepository(String url, this._key, {http.Client? client})
      : _rpcBase = '${url.replaceAll(RegExp(r'/+(rest/v1/*)?$'), '')}/rest/v1/rpc',
        _client = client ?? http.Client();

  final String _rpcBase;
  final String _key;
  final http.Client _client;

  Future<dynamic> _rpc(String fn, Map<String, Object?> args, String cacheKey) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final r = await _client
          .post(
            Uri.parse('$_rpcBase/$fn'),
            headers: {'apikey': _key, 'Authorization': 'Bearer $_key', 'Content-Type': 'application/json'},
            body: jsonEncode(args),
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw _ServerError(r.statusCode);
      final body = utf8.decode(r.bodyBytes);
      await prefs.setString('cache.$cacheKey', body);
      return jsonDecode(body);
    } catch (e) {
      // 서버 오류든 연결 끊김이든 저장본이 있으면 그걸 보여 준다.
      if (prefs.getString('cache.$cacheKey') case final cached?) return jsonDecode(cached);
      throw LoadError(offline: e is! _ServerError, lastSuccessAt: _lastSuccess(prefs));
    }
  }

  // 「마지막 정상 수집」은 저장본(날짜 목록·하루 다이제스트) 중 가장 최근 값.
  // 날짜 목록만 보면 탐색 탭을 한 번도 안 연 사람에게는 비어 있었다(에뮬레이터 QA).
  DateTime? _lastSuccess(SharedPreferences prefs) {
    final digests = <dynamic>[
      if (prefs.getString('cache.digests') case final raw?) ...(jsonDecode(raw)['digests'] as List),
      for (final k in prefs.getKeys().where((k) => k.startsWith('cache.digest.')))
        if (jsonDecode(prefs.getString(k)!) case final Map<String, dynamic> d) d,
    ];
    final times = [
      for (final d in digests)
        if (d['status'] != 'delayed' && d['last_success_at'] != null) DateTime.parse(d['last_success_at']),
    ];
    return times.isEmpty ? null : times.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  // 오늘 = KST 날짜. 배치(KST 05:00) 전이면 그날 다이제스트가 아직 없어 홈은 「아직 올라온 논문이 없어요」.
  @override
  Future<String> todayKey() async =>
      DateTime.now().toUtc().add(const Duration(hours: 9)).toIso8601String().substring(0, 10);

  // ponytail: 최근 90일치를 한 번에. 더 쌓이면 next_cursor로 이어 받기(무한 스크롤)를 붙인다.
  @override
  Future<List<Digest>> listDigests() async {
    final j = await _rpc('list_digests', {'lim': 90}, 'digests');
    return [for (final d in j['digests']) Digest.fromJson(d)];
  }

  @override
  Future<Digest?> getDigest([String? date]) async {
    date ??= await todayKey();
    final j = await _rpc('get_digest', {'d': date}, 'digest.$date');
    return j == null ? null : Digest.fromJson(j);
  }

  @override
  Future<PaperDetail> getPaper(String id) async {
    final j = await _rpc('get_paper', {'pid': id}, 'paper.$id');
    if (j == null) throw const LoadError();
    return PaperDetail.fromJson(j);
  }

  // 공식 소식·HF 트렌딩 모델(supabase/migrations/20261027100000_official_news.sql).
  // 빌드에 OFFICIAL_NEWS_PREVIEW(worker/out/official_news.define.json)를 넣으면 DB 대신 그 스냅샷을 쓴다
  // (마이그레이션이 main에 올라가기 전 실기기 확인용).
  static const _officialNewsPreview = String.fromEnvironment('OFFICIAL_NEWS_PREVIEW');

  @override
  Future<List<OfficialNews>> listOfficialNews() async {
    final j = _officialNewsPreview.isNotEmpty
        ? jsonDecode(_officialNewsPreview)
        : await _rpc('list_official_news', {'lim': 60}, 'official_news');
    return [for (final n in j['items']) OfficialNews.fromJson(n)];
  }

  @override
  Future<List<TrendingModel>> listTrendingModels() async {
    final j = _officialNewsPreview.isNotEmpty
        ? jsonDecode(_officialNewsPreview)
        : await _rpc('list_trending_models', {}, 'trending_models');
    return [for (final m in j['models'] ?? const []) TrendingModel.fromJson(m)];
  }
}

class _ServerError implements Exception {
  const _ServerError(this.status);
  final int status;
}
