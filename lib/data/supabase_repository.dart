import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'repository.dart';

// M5: Supabase 읽기 함수 3개(supabase/migrations, HANDOFF 4.3)를 공개 키로 부른다.
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

  // 「마지막 정상 수집」은 저장된 날짜 목록에서 가장 최근 값.
  DateTime? _lastSuccess(SharedPreferences prefs) {
    final raw = prefs.getString('cache.digests');
    if (raw == null) return null;
    final times = [
      for (final d in (jsonDecode(raw)['digests'] as List))
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
}

class _ServerError implements Exception {
  const _ServerError(this.status);
  final int status;
}
