import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_card.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../design/widgets/rg_row_head.dart';
import '../../design/widgets/rg_states.dart';
import '../../data/unread.dart';
import '../home/home_screen.dart';
import '../common/term_text.dart';
import 'official_news.dart';
import 'trending_models.dart';

// 공식 소식 상세(실기기 QA 요청): S02처럼 배지·제목 → AI 요약·핵심 내용(근거) → 원문 링크. 글 전체는 옮기지 않는다.
class NewsDetailScreen extends StatefulWidget {
  const NewsDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  // 이 글과 관련 소식(같은 목록에서 id로 찾는다)
  late final _req = Reloadable(() async {
    final all = await repository.listOfficialNews();
    final n = all.where((n) => n.id == widget.id).firstOrNull;
    return (n, [for (final r in n?.related ?? const <String>[]) ...all.where((x) => x.id == r)]);
  });

  // 공용 용어 사전(쌓인 논문 용어 중 승인된 것). 받기 전·실패하면 하이라이트 없이 그린다
  var _terms = const <GlossaryTerm>[];

  @override
  void initState() {
    super.initState();
    dictionary().then((t) => mounted ? setState(() => _terms = t) : null);
    // 열었으니 새 글 점을 뗀다(홈·탐색·보관함 어디서 열어도). 그리는 도중에 바꾸면 다른 화면을 다시 그리라는 요청이
    // 빌드 중에 나가 오류가 나서, 첫 프레임 뒤로 미룬다.
    WidgetsBinding.instance.addPostFrameCallback((_) => markRead('news:${widget.id}'));
  }

  @override
  void dispose() {
    _req.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _req,
      builder: (context, _) => FutureBuilder(
        future: _req.future,
        builder: (context, snap) {
          final (n, related) = snap.data ?? (null, const <OfficialNews>[]);
          return StatusBarBand(child: ListView(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, bottom: RgSpace.bottomScrollInset),
            children: [
              _TopBar(url: n?.url, actions: n == null ? null : newsActions(n, variant: RgCircleVariant.outline, share: true)),
              if (snap.hasError) RgErrorCard(error: snap.error, onRetry: _req.reload),
              if (snap.connectionState == ConnectionState.done && n == null)
                Padding(
                  padding: const EdgeInsets.all(RgSpace.gutterText),
                  child: KeepAllText('이 소식을 찾을 수 없어요', style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
                ),
              if (n != null) ..._body(n, related),
            ],
          ));
        },
      ),
    );
  }

  List<Widget> _body(OfficialNews n, List<OfficialNews> related) {
    // 요약(문장마다 줄바꿈)·핵심 내용을 한 카드로 보고 용어당 처음 1번만 강조
    final summary = n.summaryKo == null ? null : (n.thin ? n.summaryKo! : byLine(n.summaryKo!));
    final marks = cardHighlights([?summary, for (final p in n.keyPoints) p.text], _terms);
    final pointMarks = summary == null ? marks : marks.sublist(1);
    return [
    Padding(
      padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s12, RgSpace.gutterText, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 머리 줄(출처 칩 · 분류 · 날짜) → 제목 → 원제. 목록 행과 같은 머리 줄(열었으니 「새 글」은 없다)
        RgRowHead(
          chip: RgChip(n.sourceLabel, source: n.source),
          meta: n.isHot
              ? [n.isGithub ? 'GitHub' : 'Hacker News', ?n.reaction, newsDate(n)].join(' · ')
              : [newsMetaShort(n), ?n.reaction].join(' · '),
        ),
        const SizedBox(height: RgSpace.s12),
        HeadingTextScale(child: Semantics(header: true, child: KeepAllText(n.titleKo ?? n.titleEn, style: RgText.titleDetail))),
        if (n.titleKo != null) ...[
          const SizedBox(height: RgSpace.s8),
          Text(n.titleEn, style: RgText.serifSubtitle.copyWith(color: RgColors.textSecondary)),
        ],
      ]),
    ),
    const SizedBox(height: RgSpace.s24),
    // 원문이 소개문 한 줄뿐인 글: 「AI 요약」이 있는 척하지 않고 소개문 번역을 그대로 보여 준다(실기기 QA)
    if (n.thin && n.summaryKo != null) ...[
      RgCard(
        padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(n.isGithub ? '저장소 설명' : '원문 소개문', style: RgText.titleCard)),
          const SizedBox(height: RgSpace.s8),
          TermText(summary!, highlights: marks.first, style: RgText.bodySummary.copyWith(color: RgColors.textBody)),
        ]),
      ),
      const SizedBox(height: RgSpace.s12),
      _Note(n.isGithub
          ? '저장소에 적힌 설명을 AI가 한국어로 옮겼어요. 별 수는 GitHub 기준이고, 도구를 검증한 결과가 아니에요.'
          : '${n.sourceLabel} 글은 자동으로 본문을 읽을 수 없어 소개문만 옮겼어요. 자세한 내용은 원문에서 확인해 주세요.'),
    ] else if (n.summaryKo != null || n.keyPoints.isNotEmpty)
      RgCard(
        padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (n.summaryKo != null) ...[
            Semantics(header: true, child: Text('AI 요약', style: RgText.titleCard)),
            const SizedBox(height: RgSpace.s10),
            TermText(summary!, highlights: marks.first, style: RgText.bodySummary.copyWith(color: RgColors.textBody)),
          ],
          if (n.keyPoints.isNotEmpty) ...[
            if (n.summaryKo != null) const SizedBox(height: RgSpace.s24),
            Semantics(header: true, child: Text('핵심 내용', style: RgText.titleCard)),
            const SizedBox(height: RgSpace.s12),
            NewsPoints(news: n, highlights: pointMarks),
          ],
        ]),
      )
    else
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
        child: KeepAllText(
          n.isHot ? '요약이 없는 글이에요. 원문 사이트가 자동 읽기를 막았거나 아직 정리하지 못했어요. 원문에서 읽어 주세요.' : '이 글은 요약을 만들지 못했어요. 원문에서 읽어 주세요.',
          perSentence: true,
          style: RgText.bodySmall.copyWith(color: RgColors.textSecondary),
        ),
      ),
    if (!n.thin && (n.summaryKo != null || n.keyPoints.isNotEmpty)) ...[
      const SizedBox(height: RgSpace.s12),
      const _Note('원문만 보고 AI가 한국어로 정리했어요. 글 전체를 옮기지 않으니 자세한 내용은 원문에서 읽어요.'),
    ],
    // 관련 소식: 같은 모델·제품 이름이 나오는 다른 공식 자료(예: 출시 글 ↔ SDK 릴리스)
    if (related.isNotEmpty) ...[
      const SectionTitle('관련 소식'),
      RgCard(
        child: Column(children: [for (final (i, r) in related.indexed) RelatedRow(news: r, about: n, last: i == related.length - 1)]),
      ),
    ],
    const SizedBox(height: RgSpace.s28),
    // 화제·HN 반응이 붙은 소식은 Hacker News 토론으로도(댓글 수)
    _LinkCard(
      label: n.isGithub ? 'GitHub 저장소' : '원문',
      value: n.sourceLabel,
      url: n.url,
      extra: n.discussionUrl == null || n.discussionUrl == n.url
          ? null
          : ('Hacker News 토론', n.comments == null ? 'Hacker News' : '댓글 ${countKo(n.comments!)}', n.discussionUrl!),
      extraLast: true,
    ),
    ];
  }
}

// HF 트렌딩 모델 상세(P9 시안 ③·④): 한눈에 → 제작사가 내세운 강점 → 연결 논문 → 모델 카드 링크.
class ModelDetailScreen extends StatefulWidget {
  const ModelDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<ModelDetailScreen> createState() => _ModelDetailScreenState();
}

class _ModelDetailScreenState extends State<ModelDetailScreen> {
  late final _req = Reloadable(
    () async => (await repository.listTrendingModels()).where((m) => m.id == widget.id).firstOrNull,
  );
  var _terms = const <GlossaryTerm>[]; // 공용 용어 사전(강점·한계 문장 하이라이트)

  @override
  void initState() {
    super.initState();
    dictionary().then((t) => mounted ? setState(() => _terms = t) : null);
    // 열었으니 목록의 「새로 진입」을 뗀다(첫 프레임 뒤: 그리는 도중에 다른 화면을 다시 그리게 하면 오류)
    WidgetsBinding.instance.addPostFrameCallback((_) => markRead('model:${widget.id}'));
  }

  @override
  void dispose() {
    _req.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _req,
      builder: (context, _) => FutureBuilder(
        future: _req.future,
        builder: (context, snap) {
          final m = snap.data;
          return StatusBarBand(child: ListView(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, bottom: RgSpace.bottomScrollInset),
            children: [
              _TopBar(url: m?.url, actions: m == null ? null : modelActions(m, variant: RgCircleVariant.outline, share: true)),
              if (snap.hasError) RgErrorCard(error: snap.error, onRetry: _req.reload),
              if (snap.connectionState == ConnectionState.done && m == null)
                Padding(
                  padding: const EdgeInsets.all(RgSpace.gutterText),
                  child: KeepAllText('이 모델을 찾을 수 없어요', style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
                ),
              if (m != null) ..._body(m),
            ],
          ));
        },
      ),
    );
  }

  List<Widget> _body(TrendingModel m) {
    final c = m.createdAt?.toUtc().add(const Duration(hours: 9));
    final body = RgText.bodySummary.copyWith(color: RgColors.textBody);
    final marks = cardHighlights([...m.strengths, ?m.limitation], _terms);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s12, RgSpace.gutterText, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 머리 줄: 발표한 곳 칩 · 정보 출처(Hugging Face 트렌딩 순위)
          RgRowHead(
            chip: RgChip(m.maker, source: m.maker),
            meta: m.rank <= 10 ? 'Hugging Face 트렌딩 ${m.rank}위' : 'Hugging Face 최근 공개',
          ),
          const SizedBox(height: RgSpace.s12),
          HeadingTextScale(child: Semantics(header: true, child: Text(m.name, style: RgText.titleDetail))),
          const SizedBox(height: RgSpace.s8),
          Text(
            [m.author, if (c != null) '${c.year}.${c.month.toString().padLeft(2, '0')}.${c.day.toString().padLeft(2, '0')} 공개'].join(' · '),
            style: RgText.meta.copyWith(color: RgColors.textSecondary),
          ),
        ]),
      ),
      const SizedBox(height: RgSpace.s24),
      RgCard(
        padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text('한눈에', style: RgText.titleCard)),
          const SizedBox(height: RgSpace.s8),
          KeepAllText(modelLine(m), style: body),
          const SizedBox(height: RgSpace.s16),
          // 하는 일 · 크기 · 라이선스 3칸(세로 가는 선으로 나눈다)
          Container(
            padding: const EdgeInsets.only(top: RgSpace.s14),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: RgColors.dividerCard))),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _Stat('하는 일', m.taskKo, first: true),
                _Stat('크기', m.paramsKo ?? '정보 없음', muted: m.paramsKo == null),
                _Stat('라이선스', m.licenseKo ?? '정보 없음', muted: m.licenseKo == null),
              ]),
            ),
          ),
          const SizedBox(height: RgSpace.s16),
          Wrap(spacing: RgSpace.s8, runSpacing: RgSpace.s6, children: [
            RgTag(icon: 'heart', label: keepAll('좋아요 ${countKo(m.likes ?? 0)}'), height: 28),
            RgTag(icon: 'download', label: keepAll('다운로드 ${countKo(m.downloads ?? 0)}'), height: 28),
          ]),
        ]),
      ),
      const SizedBox(height: RgSpace.s12),
      RgCard(
        padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text('제작사가 내세운 강점', style: RgText.titleCard)),
          const SizedBox(height: RgSpace.s10),
          if (m.strengths.isEmpty && m.benchmarks.isEmpty)
            KeepAllText(
              m.arxiv != null ? '제작사가 모델 카드에 강점이나 평가 결과를 밝히지 않았어요. 연결된 논문에서 확인해 보세요.' : '제작사가 모델 카드에 강점이나 평가 결과를 밝히지 않았어요.',
              perSentence: true, style: body.copyWith(color: RgColors.textSecondary),
            ),
          for (final (i, s) in m.strengths.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: RgSpace.s6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s10, children: [
                Container(
                  width: 4,
                  height: 4,
                  margin: EdgeInsets.only(top: (MediaQuery.textScalerOf(context).scale(23) - 4) / 2),
                  decoration: const BoxDecoration(color: RgColors.textBody, shape: BoxShape.circle),
                ),
                Expanded(child: TermText(s, highlights: marks[i], style: body)),
              ]),
            ),
          if (m.benchmarks.isNotEmpty) ...[
            const SizedBox(height: RgSpace.s16),
            Text('제작사 측정 점수', style: RgText.meta.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: RgSpace.s4),
            for (final (i, (name, score)) in m.benchmarks.indexed)
              _Fact(name, score, sub: benchmarkKo(name), strong: true, last: i == m.benchmarks.length - 1),
          ],
          if (m.limitation case final l?) ...[
            const SizedBox(height: RgSpace.s16),
            Text('제작사가 밝힌 한계', style: RgText.meta.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: RgSpace.s6),
            TermText(l, highlights: marks.last, style: RgText.bodySmall.copyWith(color: RgColors.textBody)),
          ],
        ]),
      ),
      // 같은 모델의 양자화판·형제 모델(트렌딩에 함께 오른 것). 누르면 그 모델 카드(Hugging Face)
      if (m.variants.isNotEmpty) ...[
        const SizedBox(height: RgSpace.s12),
        RgCard(
          padding: const EdgeInsets.fromLTRB(RgSpace.s20, RgSpace.s18, RgSpace.s20, RgSpace.s6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text('함께 오른 변형 ${m.variants.length}개', style: RgText.titleCard)),
            const SizedBox(height: RgSpace.s4),
            for (final (i, v) in m.variants.indexed)
              _Fact(v.name, v.quantized ? '양자화판' : '형제 모델', sub: v.author, last: i == m.variants.length - 1, url: v.url),
          ]),
        ),
      ],
      const SizedBox(height: RgSpace.s12),
      const _Note('모델 카드에 적힌 제작사 발표를 AI가 정리했어요. 독립적으로 검증된 결과가 아니고, 평가 방식은 출처마다 달라요.'),
      const SizedBox(height: RgSpace.s28),
      _LinkCard(
        label: '모델 카드',
        value: 'Hugging Face',
        url: m.url,
        extra: m.arxiv == null ? null : ('연결된 논문', 'arXiv · ${m.arxiv}', 'https://arxiv.org/abs/${m.arxiv}'),
      ),
    ];
  }
}

// 「278억 파라미터 이미지·텍스트 이해 모델」: 목록 행·다크 카드(만든 곳은 칩에 있다)
String modelSpec(TrendingModel m) => [?m.paramsKo, '${m.taskKo} 모델'].join(' ');

// 「Qwen 공개 · 278억 파라미터 이미지·텍스트 이해 모델」: 메타데이터만으로 만든 한 줄(LLM 없음, P9 1단계)
String modelLine(TrendingModel m) => [
  '${m.author} 공개',
  [?m.paramsKo, '${m.taskKo} 모델'].join(' '),
].join(' · ');

// 상태바 밑 배경색 띠. 탭 쉘 밖(쉘 위로 푸시)이라 쉘의 띠가 없어 스크롤한 글이 시계 밑으로 비쳤다(실기기 QA). S02와 같다.
class StatusBarBand extends StatelessWidget {
  const StatusBarBand({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(children: [
    Positioned.fill(child: child),
    Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: MediaQuery.paddingOf(context).top,
      child: ColoredBox(color: RgColors.bgApp),
    ),
  ]);
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.url, this.actions});
  final String? url;
  final Widget? actions; // 공유·북마크

  @override
  Widget build(BuildContext context) => ChromeTextScale(
    child: SizedBox(
      height: RgSpace.topBar,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
        child: Row(spacing: RgSpace.s8, children: [
          RgBackButton(onTap: () => context.pop()),
          const Spacer(),
          if (url case final u?)
            RgCircleButton(
              semanticLabel: '원문 열기',
              icon: 'arrow-up-right',
              onTap: () => launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication),
            ),
          ?actions,
        ]),
      ),
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.sub, this.strong = false, this.last = false, this.url});
  final String label, value;
  final String? sub; // 벤치마크 한국어 풀이
  final bool strong, last;
  final String? url; // 있으면 줄 전체를 눌러 연다(변형 모델 카드)

  @override
  Widget build(BuildContext context) => url == null
      ? _row()
      : Semantics(
          link: true,
          child: RgPressable(row: true, onTap: () => launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication), child: _row()),
        );

  Widget _row() => Container(
    padding: EdgeInsets.only(top: RgSpace.s12, bottom: last ? 0 : RgSpace.s12),
    decoration: BoxDecoration(border: Border(top: BorderSide(color: RgColors.dividerCard))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s16, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: strong ? RgText.titleList : RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
          // 「코 / 딩 능력」처럼 낱말 중간에서 갈라지지 않게
          if (sub != null) KeepAllText(sub!, style: RgText.meta.copyWith(color: RgColors.textSecondary)),
        ]),
      ),
      // Expanded: Flexible이면 값이 글자 폭만큼만 차지해 가운데부터 왼쪽 정렬처럼 보였다(줄바꿈된 「반응」만 오른쪽 끝)
      Expanded(
        child: Text(
          keepAll(value), // 「9.6 / 만」처럼 숫자와 단위가 갈라지지 않게
          semanticsLabel: value,
          textAlign: TextAlign.end,
          style: strong ? RgText.titleSection.copyWith(fontSize: 20, fontWeight: FontWeight.w800) : RgText.bodySmall,
        ),
      ),
    ]),
  );
}

// 한눈에 한 칸: 작은 이름 + 굵은 값. 첫 칸이 아니면 왼쪽에 세로 가는 선.
class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.first = false, this.muted = false});
  final String label, value;
  final bool first, muted;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: EdgeInsets.only(left: first ? 0 : RgSpace.s12, right: RgSpace.s4),
      decoration: BoxDecoration(border: first ? null : Border(left: BorderSide(color: RgColors.dividerCard))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s2, children: [
        Text(label, style: RgText.caption.copyWith(fontSize: 12.5, color: RgColors.textSecondary)),
        KeepAllText(value, style: RgText.titleList.copyWith(color: muted ? RgColors.textSecondary : RgColors.textPrimary)),
      ]),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s6, children: [
      const Padding(padding: EdgeInsets.only(top: 2), child: RgIcon('info', size: 14, color: RgColors.textSecondary)),
      Expanded(child: KeepAllText(text, perSentence: true, style: RgText.caption.copyWith(color: RgColors.textSecondary))),
    ]),
  );
}

// 외부 링크 행(S02 정보 카드와 같은 모양, ↗)
class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.label, required this.value, required this.url, this.extra, this.extraLast = false});
  final String label, value, url;
  final (String, String, String)? extra;
  final bool extraLast; // 소식: 원문 먼저, HN 토론은 아래

  @override
  Widget build(BuildContext context) => RgCard(
    padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s4),
    child: Column(children: [
      if (!extraLast)
        if (extra case (final l, final v, final u)) _row(l, v, u, divider: true),
      _row(label, value, url, divider: extraLast && extra != null),
      if (extraLast)
        if (extra case (final l, final v, final u)) _row(l, v, u),
    ]),
  );

  Widget _row(String label, String value, String url, {bool divider = false}) => DecoratedBox(
    decoration: BoxDecoration(border: divider ? Border(bottom: BorderSide(color: RgColors.dividerCard)) : null),
    child: Semantics(
      link: true,
      label: '$label, $value 열기',
      excludeSemantics: true,
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: RgPressable(
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: RgSpace.s14),
          child: Row(spacing: RgSpace.s16, children: [
            Text(label, style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
            Expanded(child: Text(value, textAlign: TextAlign.end, style: RgText.bodySmall)),
            const RgIcon('arrow-up-right', size: 14, color: RgColors.textTertiary),
          ]),
        ),
      ),
    ),
  );
}
