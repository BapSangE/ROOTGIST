// HANDOFF 4.3 ② 하루 다이제스트, ③ 논문 상세.

// G6: 분야 코드 → 칩 이름. other는 칩 없음(「전체」에서만).
const topicLabels = {
  'llm': '언어 모델',
  'agent': '에이전트',
  'multimodal': '멀티모달',
  'optimization': '모델 최적화',
};

class PaperItem {
  PaperItem.fromJson(Map<String, dynamic> j)
      : id = j['paper_id'],
        rank = j['rank'],
        titleEn = j['title_en'],
        titleKo = j['title_ko'],
        firstAuthor = j['first_author'],
        authorCount = j['author_count'],
        publishedAt = j['published_at'],
        topic = j['topic_primary'],
        keyPoints = List<String>.from(j['key_points_preview'] ?? const []),
        ready = j['ai_status'] == 'ready';

  final String id;
  final int rank;
  final String titleEn;
  final String? titleKo;
  final String firstAuthor;
  final int authorCount;
  final String publishedAt; // YYYY-MM-DD
  final String? topic;
  final List<String> keyPoints;
  final bool ready;

  // G14: 해설 준비 중이면 영문 제목, 분야 표시 없음.
  String get title => ready ? (titleKo ?? titleEn) : titleEn;
  String? get topicLabel => ready ? topicLabels[topic] : null;
  String get authors => authorCount > 1 ? '$firstAuthor 외' : firstAuthor;
  String get date => publishedAt.replaceAll('-', '.');
}

class KeyPoint {
  KeyPoint.fromJson(Map<String, dynamic> j)
      : claim = j['claim_ko'],
        evidenceIds = List<String>.from(j['evidence_sentence_ids'] ?? const []);
  final String claim;
  final List<String> evidenceIds;
}

class Sentence {
  Sentence.fromJson(Map<String, dynamic> j)
      : id = j['sentence_id'],
        kind = j['kind'],
        text = j['text'],
        translation = j['translation_ko'];
  final String id;
  final String kind; // text | link | meta
  final String text; // 저장된 원문 그대로. 표시할 때 latexDisplay
  final String? translation;
}

class GlossaryTerm {
  GlossaryTerm.fromJson(Map<String, dynamic> j)
      : term = j['term'],
        definition = j['definition_ko'] ?? '',
        sentenceIds = List<String>.from(j['sentence_ids'] ?? const []),
        highlight = j['highlight'] == true,
        termKo = j['term_ko'],
        termKoSpan = j['term_ko_span'],
        fullForm = (j['full_form_en'] as String?)?.isEmpty ?? true ? null : j['full_form_en'],
        aliases = const [],
        papers = null;

  // 공용 용어 사전(list_terms): 공식 소식·모델 상세에서 쓴다. 뜻은 논문 하나가 아니라 사전의 뜻.
  GlossaryTerm.dictionary(Map<String, dynamic> j)
      : term = j['term'],
        definition = j['definition_ko'] ?? '',
        sentenceIds = const [],
        highlight = true,
        termKo = j['term_ko'],
        termKoSpan = null,
        fullForm = (j['full_form_en'] as String?)?.isEmpty ?? true ? null : j['full_form_en'],
        aliases = [for (final a in j['aliases'] ?? const []) a as String],
        papers = j['papers'];

  final String term;
  final List<String> aliases; // 사전 용어의 다른 영문 표기(복수형·약어)
  final int? papers; // 사전 용어: 이 용어가 쓰인 논문 수. 논문 용어는 null
  final String? termKo; // 사전에 연결된 한국어 대응어(G1·G2). 없거나 앱에 보일 수 없는 의미면 null
  final String? termKoSpan; // 이 논문 번역문에서 실제로 쓴 표기(동결된 디코더 ↔ 대응어 고정 디코더). 하이라이트는 이것 우선
  final String? fullForm; // 약어의 영문 정식 명칭(초록 풀이 또는 승인된 사전). 없으면 null
  final String definition; // G3: C02 본문은 definition_ko. context_ko는 MVP 미표시
  final List<String> sentenceIds;
  final bool highlight; // 서버 검증 결과(8.4). false면 강조하지 않는다

  // 시트 제목 아래 한국어: 승인된 대응어, 없으면 번역문에서 쓴 표기
  String? get koLabel {
    final ko = (termKo ?? termKoSpan)?.replaceFirst(RegExp(r'\s*\(.*\)$'), '');
    return ko == null || ko.isEmpty || ko.toLowerCase() == term.toLowerCase() ? null : ko;
  }

  // 한국어 글에서 찾을 표기, 먼저 찾을 것부터: 번역문 표기 → 사전 대응어 → 영문 그대로(SFT·VLM은 번역문에 남는다) → 별칭
  List<String> get koreanLabels => {
    for (final l in [termKoSpan, termKo, term, ...aliases])
      if (l != null) l.replaceFirst(RegExp(r'\s*\(.*\)$'), ''),
  }.where((l) => l.length >= 2).toList();
}

class PaperDetail {
  PaperDetail.fromJson(Map<String, dynamic> j)
      : id = j['paper_id'],
        titleEn = j['title_en'],
        titleKo = j['title_ko'],
        authors = List<String>.from(j['authors']),
        orgName = j['org_name'],
        publishedAt = j['published_at'],
        hfUrl = j['hf_url'],
        arxivUrl = j['arxiv_url'],
        topic = j['topic_primary'],
        aiStatus = j['ai_status'],
        summary = j['summary_ko'],
        // 근거 없는 핵심 내용은 출력하지 않는다(7.2).
        keyPoints = [
          for (final k in j['key_points'] ?? const [])
            if ((k['evidence_sentence_ids'] as List?)?.isNotEmpty ?? false) KeyPoint.fromJson(k),
        ],
        sentences = [for (final s in j['sentences'] ?? const []) Sentence.fromJson(s)],
        glossary = [for (final g in j['glossary'] ?? const []) GlossaryTerm.fromJson(g)];

  final String id;
  final String titleEn;
  final String? titleKo;
  final List<String> authors;
  final String? orgName;
  final String publishedAt;
  final String hfUrl;
  final String arxivUrl;
  final String? topic;
  final String aiStatus; // ready | pending | failed
  bool get ready => aiStatus == 'ready';
  final String? summary;
  final List<KeyPoint> keyPoints;
  final List<Sentence> sentences;
  final List<GlossaryTerm> glossary;

  String get title => ready ? (titleKo ?? titleEn) : titleEn;
  String? get topicLabel => ready ? topicLabels[topic] : null;
  String get authorLine => authors.length > 1 ? '${authors.first} 외' : authors.firstOrNull ?? '';
  String get date => publishedAt.replaceAll('-', '.');
  Sentence? sentence(String id) => sentences.where((s) => s.id == id).firstOrNull;
}

// 문장 ID → 사용자 문구 번호. A02 → 2 (7.2).
int sentenceNumber(String id) => int.parse(id.substring(1));

// HANDOFF 8.3 (A6): 저장값은 그대로 두고 표시할 때만 변환한다.
String latexDisplay(String s) => s
    .replaceAllMapped(RegExp(r'\\([%_&#$])'), (m) => m[1]!)
    .replaceAll(RegExp(r'(?<=\d)\s*\\times\s*(?=\d)'), '×') // 3 \times 4 → 3×4
    .replaceAll(RegExp(r'(?<=\d)\s*\\times\b'), '×') // 10\times faster → 10× faster
    .replaceAll(RegExp(r'~|\\,'), ' ');

// ① 날짜 목록 항목과 ② 하루 다이제스트를 같이 쓴다. 목록 항목에는 papers가 없다.
class Digest {
  Digest.fromJson(Map<String, dynamic> j)
      : date = DateTime.parse(j['digest_date']),
        status = j['status'],
        paperCount = j['paper_count'] ?? (j['papers'] as List?)?.length ?? 0,
        primaryTopic = j['primary_topic'],
        lastSuccessAt = j['last_success_at'] == null ? null : DateTime.parse(j['last_success_at']),
        papers = [for (final p in j['papers'] ?? const []) PaperItem.fromJson(p)]
          ..sort((a, b) => a.rank.compareTo(b.rank));

  final DateTime date;
  final String status; // published | empty | delayed
  final int paperCount;
  final String? primaryTopic; // G10
  final DateTime? lastSuccessAt; // UTC
  final List<PaperItem> papers;

  String get dateKey => date.toIso8601String().substring(0, 10);
}

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];
String koreanDate(DateTime d) => '${d.month}월 ${d.day}일 ${_weekdays[d.weekday - 1]}요일';

// 8.2: 시각은 KST로 보인다.
String kstTime(DateTime utc) {
  final k = utc.toUtc().add(const Duration(hours: 9));
  return '${k.hour.toString().padLeft(2, '0')}:${k.minute.toString().padLeft(2, '0')}';
}

String kstDateTime(DateTime utc) {
  final k = utc.toUtc().add(const Duration(hours: 9));
  return '${k.month}월 ${k.day}일 ${kstTime(utc)}';
}

// 연구소 공식 소식(PROPOSALS P8d). 제목·출처·날짜·링크만, 본문은 옮기지 않는다. 모양은 worker/official_news.py 출력.
class OfficialNews {
  OfficialNews.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? j['url'], // 상세 화면 주소. fixture에는 없어 url로
        source = j['source'],
        sourceLabel = j['source_label'],
        kind = j['kind'] ?? 'post',
        summaryKo = j['summary_ko'],
        keyPoints = [for (final k in j['key_points'] ?? const []) NewsPoint.fromJson(k)],
        category = j['category'],
        titleEn = j['title_en'],
        titleKo = j['title_ko'],
        publishedAt = DateTime.parse(j['published_at']),
        url = j['url'],
        thin = j['thin'] ?? false,
        related = [for (final r in j['related'] ?? const []) r as String];

  final String id;
  final String source; // openai, anthropic, …
  final String sourceLabel;
  final String kind; // post(블로그 글) | notice(커뮤니티 공지) | release(릴리스 묶음)
  final String? summaryKo; // AI 요약 1~2문장(원문 근거만). 릴리스는 없음
  final List<NewsPoint> keyPoints; // 핵심 내용 최대 3개
  final String? category; // 피드의 분류(원문)
  final String titleEn;
  final String? titleKo; // 제목만 LLM이 옮긴다. 없으면 원문 제목만
  final DateTime publishedAt; // UTC
  final String url;
  // 원문이 피드 소개문 한 줄뿐(OpenAI 글 페이지는 자동 접근을 막는다). summaryKo는 요약이 아니라 그 소개문의 번역
  final bool thin;
  final List<String> related; // 모델·제품 이름이 겹치는 다른 소식 id(수집기가 잇는다)

  bool get isUpdate => kind != 'post'; // 「업데이트」 칸(공지·릴리스)

  // 근거 문장으로 바로 여는 원문 주소(브라우저 텍스트 위치 링크 #:~:text=). 인용이 없으면 글 주소.
  String evidenceUrl(NewsPoint p) =>
      p.quote == null ? url : '$url#:~:text=${Uri.encodeComponent(p.quote!)}';

  // 분류는 개발 소식에 가까운 것만 한국어로. 나머지(Google Research 주제 등)는 표시하지 않는다.
  String? get categoryKo => switch (category) {
    'Research' => '연구',
    'Product' => '제품',
    'Safety' || 'Safety & Alignment' => '안전',
    'Publication' => '논문',
    'News' => '소식',
    'Announcement' => '공지',
    'Release' => '릴리스',
    'AI Research' || 'NVIDIA Research' => '연구', // Meta 엔지니어링 블로그·NVIDIA
    'Hugging Face Blog' => 'Hugging Face 블로그', // HF 블로그에 회사 계정이 쓴 글(칩은 그 회사)
    _ => null,
  };
}

// 공식 소식 핵심 내용 1개. para·quote는 원문 근거(몇 번째 문단, 그 문단의 짧은 원문 구절). 릴리스는 근거 없이 문장만.
class NewsPoint {
  NewsPoint.fromJson(Map<String, dynamic> j)
      : text = j['text'],
        para = j['para'],
        quote = j['quote'];

  final String text;
  final int? para; // 1부터
  final String? quote; // 화면에 보이지 않는다. 원문 링크의 위치 지정에만 쓴다
}

// Hugging Face 트렌딩 모델(PROPOSALS P9). 메타데이터 + 모델 카드에 적힌 제작사 주장(card). 모양은 worker/official_news.py 출력.
class TrendingModel {
  TrendingModel.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        author = j['author'],
        name = j['name'],
        task = j['task'],
        params = j['params'],
        license = j['license'],
        likes = j['likes'],
        downloads = j['downloads'],
        createdAt = j['created_at'] == null ? null : DateTime.parse(j['created_at']),
        rank = j['rank'],
        arxiv = (j['arxiv'] as List?)?.firstOrNull,
        url = j['url'],
        strengths = [for (final s in j['card']?['strengths'] ?? const []) s as String],
        benchmarks = [for (final b in j['card']?['benchmarks'] ?? const []) (b['name'] as String, b['score'] as String)],
        limitation = j['card']?['limitation'],
        variants = [for (final v in j['variants'] ?? const []) ModelVariant.fromJson(v)];

  final String id; // 만든곳/이름
  final String author, name;
  final String? task; // pipeline_tag
  final int? params;
  final String? license;
  final int? likes, downloads;
  final DateTime? createdAt;
  final int rank;
  final String? arxiv;
  final String url;
  final List<String> strengths; // 비면 「제작사가 밝히지 않았어요」
  final List<(String, String)> benchmarks; // (이름, 점수) 제작사 측정
  final String? limitation;
  final List<ModelVariant> variants; // 같은 모델의 양자화판·형제 모델(수집기가 묶는다)

  // 발표한 곳(칩). HF 계정 이름을 알려진 회사 이름으로, 모르면 계정 이름 그대로
  String get maker => makerName(author);

  // 「새로 나옴」 칸: 최근 14일 안에 공개(worker NEW_DAYS)
  bool isNew(DateTime now) => createdAt != null && now.difference(createdAt!).inDays < 14;

  String get taskKo => switch (task) {
    'text-generation' => '텍스트 생성',
    'image-text-to-text' => '이미지·텍스트 이해',
    'text-to-image' => '이미지 생성',
    'image-to-image' => '이미지 편집',
    'image-to-video' => '이미지 → 영상 생성',
    'text-to-video' => '영상 생성',
    'text-to-speech' => '음성 합성',
    'automatic-speech-recognition' => '음성 인식',
    'any-to-any' => '여러 입출력',
    'feature-extraction' || 'sentence-similarity' => '임베딩',
    _ => task ?? '과제 정보 없음',
  };

  // 278억 파라미터, 1.2조 파라미터
  String? get paramsKo {
    final p = params;
    if (p == null) return null;
    if (p >= 1e12) return '${(p / 1e12).toStringAsFixed(1)}조 파라미터';
    return '${_comma((p / 1e8).round())}억 파라미터';
  }

  String? get licenseKo => switch (license) {
    null => null,
    'other' => '개별 라이선스',
    final l => l.toUpperCase() == 'MIT' ? 'MIT' : l.replaceFirstMapped(RegExp(r'^apache'), (_) => 'Apache'),
  };
}

// Hugging Face 계정 → 회사 이름(모델 칩). 목록에 없는 계정은 그대로 보인다.
const _makers = {
  'deepseek-ai': 'DeepSeek', 'Qwen': 'Qwen', 'google': 'Google', 'facebook': 'Meta', 'meta-llama': 'Meta',
  'mistralai': 'Mistral AI', 'nvidia': 'NVIDIA', 'tencent': 'Tencent', 'baidu': 'Baidu', 'MiniMaxAI': 'MiniMax',
  'LiquidAI': 'Liquid AI', 'black-forest-labs': 'Black Forest Labs', 'openbmb': 'OpenBMB', 'inclusionAI': 'inclusionAI',
  'microsoft': 'Microsoft', 'openai': 'OpenAI', 'anthropic': 'Anthropic', 'ibm-granite': 'IBM', 'allenai': 'Ai2',
  'HuggingFaceTB': 'Hugging Face', 'HuggingFaceBio': 'Hugging Face', 'moonshotai': 'Moonshot AI', 'zai-org': 'Z.ai',
  'OpenMOSS-Team': 'OpenMOSS', 'KRAFTON': 'KRAFTON', 'kyutai': 'Kyutai', 'Lightricks': 'Lightricks', 'fishaudio': 'Fish Audio',
};
String makerName(String author) => _makers[author] ?? author;

class ModelVariant {
  ModelVariant.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        name = j['name'],
        author = j['author'],
        quantized = j['quantized'] == true;
  final String id, name, author;
  final bool quantized; // GGUF·FP8 같은 양자화판
  String get url => 'https://huggingface.co/$id';
}

// 숫자: 1,234 / 8.5만 / 776만
String _comma(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
String countKo(int n) => n >= 10000 ? '${(n / 10000).toStringAsFixed(n < 100000 ? 1 : 0)}만' : _comma(n);

// 모델 카드에 자주 나오는 벤치마크의 한국어 풀이. 없는 이름은 풀이 없이 이름만(P9).
String? benchmarkKo(String name) {
  final n = name.toLowerCase();
  if (n.contains('swe-bench')) return '실제 GitHub 이슈를 고치는 코딩 능력';
  if (n.contains('terminal-bench')) return '터미널에서 명령으로 일을 끝내는 능력';
  if (n.contains('gpqa')) return '대학원 수준 과학 문제 풀이';
  if (n.contains('livecodebench') || n.contains('humaneval')) return '코딩 문제 풀이';
  if (n.contains('aime') || n.contains('math')) return '수학 문제 풀이';
  if (n.contains('mmlu')) return '여러 분야 지식 문제';
  if (n.contains('mmmu')) return '이미지가 섞인 전문 문제 풀이';
  return null;
}
