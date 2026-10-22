// HANDOFF 4.3 ② 하루 다이제스트. 상세(③)는 S02에서 추가한다.

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
