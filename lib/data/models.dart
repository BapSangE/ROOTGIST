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
        ready = j['ai_status'] == 'ready',
        summary = j['summary_ko'],
        // 근거 없는 핵심 내용은 출력하지 않는다(7.2).
        keyPoints = [
          for (final k in j['key_points'] ?? const [])
            if ((k['evidence_sentence_ids'] as List?)?.isNotEmpty ?? false) KeyPoint.fromJson(k),
        ],
        sentences = [for (final s in j['sentences'] ?? const []) Sentence.fromJson(s)];

  final String id;
  final String titleEn;
  final String? titleKo;
  final List<String> authors;
  final String? orgName;
  final String publishedAt;
  final String hfUrl;
  final String arxivUrl;
  final String? topic;
  final bool ready;
  final String? summary;
  final List<KeyPoint> keyPoints;
  final List<Sentence> sentences;

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

class Digest {
  Digest.fromJson(Map<String, dynamic> j)
      : date = DateTime.parse(j['digest_date']),
        status = j['status'],
        papers = [for (final p in j['papers'] ?? const []) PaperItem.fromJson(p)]
          ..sort((a, b) => a.rank.compareTo(b.rank));

  final DateTime date;
  final String status; // published | empty | delayed
  final List<PaperItem> papers;
}
