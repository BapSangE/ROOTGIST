import '../../data/models.dart';

// 홈 「오늘의 브리핑」(design-preview/src/briefing_preview.html): 최근 24시간 소식을 모아 주요 소식 5개를 고른다.
// 화면과 떼어 테스트한다. 사건 묶기·중요도 점수를 배치(LLM)로 옮기기 전까지는 아래 간단한 규칙으로 고른다.
class Briefing {
  Briefing(List<OfficialNews> all, DateTime now, {int top = 5}) {
    bool within(OfficialNews n, Duration d) => now.difference(n.publishedAt) <= d;
    final news = [for (final n in all) if (!n.isHot) n];
    final hot = [for (final n in all) if (n.isHot && within(n, const Duration(hours: 48))) n];
    final day = [for (final n in news) if (within(n, const Duration(hours: 24))) n];
    final days3 = [for (final n in news) if (within(n, const Duration(days: 3))) n];
    // 「새 소식 N건」은 24시간 기준(공식 소식 + 화제). 공식 소식이 3건도 안 되면(주말·조용한 날) 3일로 넓힌다
    wide = day.length < 3;
    final counted = wide ? days3 : day;
    total = counted.length + hot.where((n) => within(n, const Duration(hours: 24))).length;
    // 주요 소식은 3일 안의 공식 소식 + 크게 화제가 된 글(HN 500점 이상이거나 모델 출시)에서 고른다.
    // 공식 출처가 없는 발표(예: Mistral 가중치 공개)도 화제 덕에 올라온다. 오래될수록 하루 1점씩 깎인다.
    stale = days3.isEmpty && hot.isEmpty;
    final big = [for (final n in hot) if (!n.isGithub && ((n.points ?? 0) >= 500 || _launch.hasMatch(n.titleEn))) n];
    final pool = stale ? news.take(10).toList() : [...days3, ...big];
    final ranked = [...pool]..sort((a, b) => importance(b, now).compareTo(importance(a, now)));
    stories = ranked.take(top).toList();
    // 나머지 = 세어진 새 소식 중 주요 소식에 안 든 것(최신순, 받은 순서 그대로). 최근 소식 모드면 남은 최근 소식
    rest = [for (final n in stale ? pool : counted) if (!stories.contains(n)) n];
    updates = counted.where((n) => n.isUpdate).length;
    // 개발자 화제: 주요 소식에 오르지 않은 Hacker News 글, 점수 순(GitHub 새 도구는 탐색의 화제 칸에)
    talk = [for (final n in hot) if (!n.isGithub && !stories.contains(n)) n]..sort((a, b) => (b.points ?? 0).compareTo(a.points ?? 0));
    hotCount = hot.length;
  }

  late final bool wide; // true면 「최근 3일」
  late final bool stale; // true면 3일 안에 새 소식이 없어 최근 소식을 대신 보인다(새 소식 0건)
  late final List<OfficialNews> stories; // 오늘의 주요 소식(중요한 순)
  late final List<OfficialNews> rest; // 나머지 새 소식(최신순)
  late final List<OfficialNews> talk; // 개발자 화제(점수 순)
  late final int total;
  late final int updates; // 그중 바뀐 도구(공지·릴리스)
  late final int hotCount; // 화제 칸의 글 수(최근 이틀)
}

// 모델 출시: 이름 뒤에 번호가 붙은 모델(GPT-6.1, Gemini 4, Claude 5, Mistral Large 4, Qwen3.8, DeepSeek-V4 …).
// 「Introducing·Announcing」은 블로그 제목에 너무 흔해(HF 글 대부분) 출시 신호로 쓰지 않는다(실데이터 2026-10-30).
final _launch = RegExp(
  r'\b(gpt|gemini|claude|llama|mistral|grok|qwen|deepseek|nemotron|gemma|phi|sora|veo|imagen)(?:[- ]?v?\d|[- ](?!code\b)\w+ \d)',
  caseSensitive: false,
);
const _majors = {'openai', 'anthropic', 'deepmind', 'google_research', 'meta', 'google'};

/// 중요도: 글(발표) > 공지 > 릴리스(화제는 HN 점수), 큰 연구소, 번호 붙은 모델 출시, 같은 사건을 다룬 다른 글 수, 새로울수록.
double importance(OfficialNews n, DateTime now) {
  // 화제 글은 HN 점수로(300점마다 1점, 최대 4점). 공식 소식은 글 종류로
  final kind = n.isHot ? 1 + ((n.points ?? 0) / 300).clamp(0, 4) : switch (n.kind) { 'post' => 3.0, 'notice' => 2.0, _ => 1.0 };
  final major = _majors.contains(n.source) ? 2.0 : 0.0;
  final launch = _launch.hasMatch(n.titleEn) ? 3.0 : 0.0;
  final related = n.related.length.clamp(0, 2).toDouble();
  final age = now.difference(n.publishedAt).inMinutes / (60 * 24); // 하루 지날 때마다 1점
  return kind + major + launch + related - age;
}

/// 「12분 전」 「3시간 전」 「2일 전」 한 형식(디자인 피드백 2026-10-31 3번: 「어제 18:00」 「10월 29일」이 섞여 있었다).
/// 24시간 안은 시간, 그 뒤는 KST 날짜 차이로 「N일 전」. 한 달이 넘으면 날짜.
String relativeKo(DateTime utc, DateTime now) {
  final d = now.difference(utc);
  if (d.inMinutes < 1) return '방금';
  if (d.inMinutes < 60) return '${d.inMinutes}분 전';
  if (d.inHours < 24) return '${d.inHours}시간 전';
  final k = utc.toUtc().add(const Duration(hours: 9)), today = now.toUtc().add(const Duration(hours: 9));
  final days = DateTime(today.year, today.month, today.day).difference(DateTime(k.year, k.month, k.day)).inDays;
  if (days > 30) return '${k.month}월 ${k.day}일';
  return '${days < 1 ? 1 : days}일 전';
}

/// 「오늘 · 10월 30일」 「어제 · 10월 29일」 「10월 27일」(공식 소식 목록의 날짜 머리)
String dayHeaderKo(DateTime utc, DateTime now) {
  final k = utc.toUtc().add(const Duration(hours: 9)), today = now.toUtc().add(const Duration(hours: 9));
  final days = DateTime(today.year, today.month, today.day).difference(DateTime(k.year, k.month, k.day)).inDays;
  final date = '${k.month}월 ${k.day}일';
  return switch (days) { 0 => '오늘 · $date', 1 => '어제 · $date', _ => date };
}

/// 「아침 브리핑」 「저녁 브리핑」: 지금 시각(KST)에 맞춘 이름
String briefingLabel(DateTime now) {
  final h = now.toUtc().add(const Duration(hours: 9)).hour;
  return h >= 5 && h < 11 ? '아침 브리핑' : h < 17 && h >= 11 ? '낮 브리핑' : h >= 17 && h < 23 ? '저녁 브리핑' : '밤 브리핑';
}

/// 공식 소식 거르기 칩: 출처 19개 대신 회사 묶음. 같은 회사의 블로그·커뮤니티·SDK·Hugging Face 계정 글을 한 칩으로.
String newsGroup(String source) => switch (source) {
  'openai' || 'openai_community' || 'openai_sdk' => 'OpenAI',
  'anthropic' || 'claude_code' || 'claude_api' || 'anthropic_sdk' => 'Anthropic',
  'deepmind' || 'google_research' || 'google' => 'Google',
  'meta' => 'Meta',
  'nvidia' || 'nvidia_dev' => 'NVIDIA',
  _ => '기타',
};
const newsGroups = ['OpenAI', 'Anthropic', 'Google', 'Meta', 'NVIDIA', '기타'];
