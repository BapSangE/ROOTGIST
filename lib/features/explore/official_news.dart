import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../common/term_text.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_card.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../design/widgets/rg_underline_tabs.dart';
import '../../design/widgets/rg_states.dart';
import '../../data/unread.dart';
import '../home/briefing.dart';
import '../../design/widgets/rg_row_head.dart';
import '../common/item_actions.dart';
import '../home/home_sections.dart';
import 'date_groups.dart';

// S04 「공식 소식」 칸(PROPOSALS P8d·P9 A안). 발표(연구소 블로그) | 업데이트(커뮤니티 공지·릴리스).
// 글마다 AI 요약과 핵심 내용만 한국어로 보이고, 핵심 내용은 원문의 근거 문단으로, 상세는 원문 링크로 보낸다.
class OfficialNewsSection extends StatefulWidget {
  const OfficialNewsSection({super.key});

  @override
  State<OfficialNewsSection> createState() => _OfficialNewsSectionState();
}

class _OfficialNewsSectionState extends State<OfficialNewsSection> {
  final _req = Reloadable(repository.listOfficialNews);
  late var _tab = newsTab.value = exploreJump.value?.newsTab ?? 0; // 0 발표, 1 업데이트, 2 화제
  bool get _updates => _tab == 1;
  String? _source; // null = 전체
  String? _hot; // 개발자 화제 칩: null 전체, 'hn', 'github'

  // 홈 「업데이트 더 보기」로 들어오면 업데이트를, 「공식 발표 더 보기」면 발표를 고른다
  void _jump() {
    final j = exploreJump.value;
    if (j != null && j.tab == 1 && mounted) {
      setState(() {
        _tab = newsTab.value = j.newsTab;
        _source = null;
        _hot = null;
      });
    }
  }

  // 「여기까지 봤어요」: 이 화면을 열기 전 값(이번에 연 뒤에는 맨 위 글 시각으로 바꾼다)
  final DateTime? _seenBefore = newsSeenAt.value;

  // 지난번에 본 글 중 가장 새것(선은 그 글 바로 위에)
  OfficialNews? _firstSeen(List<OfficialNews> list) =>
      _seenBefore == null ? null : list.where((n) => n.publishedAt.compareTo(_seenBefore) <= 0).firstOrNull;

  @override
  void initState() {
    super.initState();
    exploreJump.addListener(_jump);
    // 목록을 받으면 이번 맨 위 발표 시각을 기록(다음에 열 때 선 자리). 그리는 도중이 아니라 다음 프레임에
    _req.future.then((all) {
      final newest = all.where((n) => !n.isUpdate && !n.isHot).map((n) => n.publishedAt).fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
      if (newest != null) WidgetsBinding.instance.addPostFrameCallback((_) => newsSeenAt.value = newest);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    exploreJump.removeListener(_jump);
    _req.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _req,
      builder: (context, _) => FutureBuilder(
        future: _req.future,
        builder: (context, snap) => ListView(
          padding: const EdgeInsets.only(bottom: RgSpace.bottomScrollInset),
          children: [
            const SizedBox(height: RgSpace.s12),
            // 밑줄 탭: 위 알약 세그먼트(논문·공식 소식·모델)와 위계를 나눈다
            RgUnderlineTabs(
              labels: const ['발표', '업데이트', '개발자 화제'], // 홈 「개발자 화제」 배지·카드와 같은 이름
              selected: _tab,
              onTap: (i) => setState(() {
                _tab = newsTab.value = i;
                _source = null;
                _hot = null;
              }),
            ),
            ...switch (snap) {
              AsyncSnapshot(hasError: true) => [
                const SizedBox(height: RgSpace.s20),
                RgErrorCard(error: snap.error, onRetry: _req.reload),
              ],
              AsyncSnapshot(connectionState: ConnectionState.done) => _list(context, snap.data!),
              _ => const [
                RgSkeleton(child: Padding(padding: EdgeInsets.only(top: RgSpace.s20), child: RgSkeletonRows(count: 4))),
              ],
            },
          ],
        ),
      ),
    );
  }

  List<Widget> _list(BuildContext context, List<OfficialNews> all) {
    if (_tab == 2) return _hotList(context, all);
    final kind = [for (final n in all) if (!n.isHot && n.isUpdate == _updates) n];
    if (kind.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s24, RgSpace.gutterText, 0),
          child: KeepAllText('아직 모은 소식이 없어요', style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
        ),
      ];
    }
    // 칩은 회사 묶음(출처 19개 → 6개, 시안 C). 순서는 고정(글 순서대로면 날마다 칩 자리가 바뀐다)
    final present = {for (final n in kind) newsGroup(n.source)};
    final sources = [for (final g in newsGroups) if (present.contains(g)) MapEntry(g, g)];
    final shown = [for (final n in kind) if (_source == null || newsGroup(n.source) == _source) n];
    final now = clock();
    return [
      const SizedBox(height: RgSpace.s14),
      SizedBox(
        height: RgFilterChip.touchHeight(context),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
          children: [
            for (final (id, label) in [(null, '전체'), ...sources.map((e) => (e.key, e.value))]) ...[
              RgFilterChip(label: label, selected: _source == id, onTap: () => setState(() => _source = id)),
              const SizedBox(width: RgSpace.s8),
            ],
          ],
        ),
      ),
      // 홈 카드 모양(2026-11-01): 발표는 한 묶음(하루·주·달)에 흰 카드 하나(홈 「오늘의 주요 소식」 행), 업데이트는 글마다 회사 색 카드(홈 「바뀐 도구」).
      // 최근 7일은 하루씩, 그 앞은 주·달·해로 묶어 날짜 줄로 접는다(DateGroups, 「지난 논문」 모양). 발표·업데이트나 출처 칩을 바꾸면 목록이 떠오르며 바뀐다(RgFilterSwitch)
      RgFilterSwitch(
        switchKey: (_tab, _source),
        child: DateGroups<OfficialNews>(
          key: ValueKey((_tab, _source)),
          items: shown,
          at: (n) => n.publishedAt,
          tag: (n) => n.sourceLabel,
          now: now,
          builder: (context, rows) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
            child: _updates
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: RgSpace.s10, children: [
                    for (final n in rows) HomeUpdateCard(news: n, now: now),
                  ])
                : HomeCard(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
                    child: FutureBuilder(
                      future: dictionary(),
                      initialData: dictionaryValue,
                      builder: (context, snap) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 32, children: [
                        for (final (i, n) in rows.indexed) ...[
                          // 지난번에 본 맨 위 글 앞에 「여기까지 봤어요」 선
                          if (_seenBefore case final seen? when n.publishedAt.compareTo(seen) <= 0 && shown.first.publishedAt.isAfter(seen) && _firstSeen(shown) == n)
                            const _ReadLine(),
                          HomeStoryRow(news: n, now: now, last: i == rows.length - 1, keywords: newsKeywords(n, snap.data ?? const []), explore: true),
                        ],
                      ]),
                    ),
                  ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s12, RgSpace.gutterText, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s6, children: [
          Padding(padding: EdgeInsets.only(top: 2), child: RgIcon('info', size: 14, color: RgColors.textSecondary)),
          Expanded(
            child: KeepAllText(
              _updates
                  ? '공지 요약과 릴리스 노트 요약은 AI가 원문만 보고 정리했어요. 정확한 내용은 원문에서 확인해요.'
                  : '제목·요약·핵심 내용은 AI가 원문만 보고 한국어로 정리했어요. 글 전체를 옮기지 않으니 자세한 내용은 원문에서 읽어요.',
              perSentence: true, style: RgText.caption.copyWith(color: RgColors.textSecondary),
            ),
          ),
        ]),
      ),
    ];
  }

  // 개발자 화제 칸: 「전체 | Hacker News | GitHub」 칩(발표·업데이트의 출처 칩과 같은 자리), 홈 개발자 화제 카드를 날짜로 묶어.
  // 점수 단위가 달라(HN 추천 · GitHub 별) 한 줄로 섞어 세우지 않는다: 각자 점수 순, 「전체」는 둘을 한 개씩 번갈아 놓는다.
  List<Widget> _hotList(BuildContext context, List<OfficialNews> all) {
    final now = clock();
    int byPoints(OfficialNews a, OfficialNews b) => (b.points ?? 0).compareTo(a.points ?? 0);
    final hn = [for (final n in all) if (n.isHot && !n.isGithub) n]..sort(byPoints);
    final gh = [for (final n in all) if (n.isGithub) n]..sort(byPoints);
    final shown = switch (_hot) {
      'hn' => hn,
      'github' => gh,
      _ => [for (var i = 0; i < hn.length || i < gh.length; i++) ...[if (i < hn.length) hn[i], if (i < gh.length) gh[i]]],
    };
    return [
      const SizedBox(height: RgSpace.s14),
      SizedBox(
        height: RgFilterChip.touchHeight(context),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
          children: [
            for (final (id, label) in [(null, '전체'), if (hn.isNotEmpty) ('hn', 'Hacker News'), if (gh.isNotEmpty) ('github', 'GitHub')]) ...[
              RgFilterChip(label: label, selected: _hot == id, onTap: () => setState(() => _hot = id)),
              const SizedBox(width: RgSpace.s8),
            ],
          ],
        ),
      ),
      RgFilterSwitch(
        switchKey: (_tab, _hot),
        child: shown.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s24, RgSpace.gutterText, 0),
                child: KeepAllText('아직 모은 개발자 화제가 없어요', style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
              )
            : DateGroups<OfficialNews>(
                key: ValueKey(_hot),
                items: shown,
                at: (n) => n.publishedAt,
                tag: (n) => n.sourceLabel,
                now: now,
                builder: (context, rows) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: RgSpace.s16, children: [
                    for (final n in rows) HomeTalkCard(news: n, now: now, explore: true),
                  ]),
                ),
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s12, RgSpace.gutterText, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s6, children: [
          Padding(padding: EdgeInsets.only(top: 2), child: RgIcon('info', size: 14, color: RgColors.textSecondary)),
          Expanded(
            child: KeepAllText(
              '개발자들이 많이 본 글과 새 도구예요. 공식 발표가 아니라 각 사이트의 글이고, 숫자는 Hacker News 추천(upvote)·댓글 수와 GitHub 별 수예요. 요약은 원문 사이트가 허용할 때만 AI가 만들어요.',
              perSentence: true, style: RgText.caption.copyWith(color: RgColors.textSecondary),
            ),
          ),
        ]),
      ),
    ];
  }
}

// 상세 화면 「관련 소식」 한 줄: 출처·날짜 + 제목, 그리고 두 글을 잇는 문장(관련 글의 핵심 내용 중 겹치는 이름이 나오는 것).
class RelatedRow extends StatelessWidget {
  const RelatedRow({super.key, required this.news, required this.about, required this.last});
  final OfficialNews news;
  final OfficialNews about; // 지금 보고 있는 글
  final bool last;

  @override
  Widget build(BuildContext context) {
    final n = news;
    final hint = relatedHint(n, about);
    return RgListRow(
      showDivider: !last,
      onTap: () => context.push('/news/${Uri.encodeComponent(n.id)}'),
      trailing: Padding(
        padding: EdgeInsets.only(top: 2, right: RgSpace.s12),
        child: RgIcon('chevron-right', size: 18, color: RgColors.textTertiary),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        NewsHead(news: n),
        const SizedBox(height: RgSpace.s6),
        KeepAllText(n.titleKo ?? n.titleEn, style: RgText.titleList),
        if (hint != null) ...[
          const SizedBox(height: RgSpace.s4),
          KeepAllText(hint, style: RgText.bodySmall.copyWith(color: RgColors.textBody)),
        ],
      ]),
    );
  }
}

// 관련 글의 핵심 내용 중 지금 글 제목의 이름(gpt-6.1-terra 등)이 나오는 문장. 없으면 null.
String? relatedHint(OfficialNews related, OfficialNews about) {
  final key = RegExp(r'[a-z]+-\d+(?:\.\d+)*(?:-[a-z]+)?')
      .allMatches(about.titleEn.toLowerCase().replaceAll(RegExp(r'\s+'), '-'))
      .map((m) => m.group(0)!)
      .where((n) => n.length >= 7)
      .toList();
  for (final p in related.keyPoints) {
    final t = p.text.toLowerCase().replaceAll(RegExp(r'\s+'), '-');
    if (key.any((k) => t.contains(k.replaceFirst(RegExp(r'^(introducing|developing|building)-'), '')))) return p.text;
  }
  return null;
}

// 공식 소식 머리 줄: 출처 이름 칩(회사 연한 색) · 시각 · 「새 글」 점. 분류는 위계를 흐려 뺐다(피드백 4번). 출처 칩은 로고 대신 이름 글자만(docs/RIGHTS.md 4장).
// release: 바뀐 도구 줄은 분류 대신 버전·건수(「v0.0.3 · 3건」)
class NewsHead extends StatelessWidget {
  const NewsHead({super.key, required this.news, this.release = false});
  final OfficialNews news;
  final bool release;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: readItems,
    builder: (context, _, _) => RgRowHead(
      chip: RgChip(news.sourceLabel, source: news.source),
      meta: news.isHot
          ? [?news.reaction, relativeKo(news.publishedAt, clock())].join(' · ')
          : release
              ? [releaseTag(news), relativeKo(news.publishedAt, clock()), ?news.reaction].join(' · ')
              : [relativeKo(news.publishedAt, clock()), ?news.reaction].join(' · '),
      isNew: isNew(newsKey(news), news.publishedAt),
    ),
  );
}

String releaseTag(OfficialNews n) {
  if (n.kind != 'release') return '공지';
  final ver = RegExp(r'v[\d.]+(?:~(v[\d.]+))?').firstMatch(n.titleEn);
  final count = RegExp(r'\((\d+) (?:releases?|changes?)\)').firstMatch(n.titleEn)?.group(1);
  final last = ver == null ? null : (ver.group(1) ?? ver.group(0));
  return [?last, if (count != null) '$count건'].join(' · ');
}

String newsKey(OfficialNews n) => 'news:${n.id}';
bool hasNewNews(Iterable<OfficialNews> news) => news.any((n) => isNew(newsKey(n), n.publishedAt));

ItemActions newsActions(OfficialNews n, {RgCircleVariant variant = RgCircleVariant.neutral, bool share = false, double? visualSize}) => ItemActions(
  id: n.id,
  title: n.titleKo ?? n.titleEn,
  url: n.url,
  source: n.sourceLabel,
  kind: 'news',
  variant: variant,
  share: share,
  visualSize: visualSize,
);

// 머리 줄용: 출처는 칩이 보여 주므로 분류 · 날짜만
String newsMetaShort(OfficialNews n) => [?n.categoryKo, newsDate(n)].join(' · ');

String newsDate(OfficialNews n) {
  final k = n.publishedAt.toUtc().add(const Duration(hours: 9));
  return '${k.month}월 ${k.day}일';
}

// 번호 붙은 핵심 내용. 근거가 있으면 「근거 · 원문 N번째 문단 ›」 → 원문의 그 구절 위치로.
class NewsPoints extends StatelessWidget {
  const NewsPoints({super.key, required this.news, this.highlights});
  final OfficialNews news;
  final List<List<Highlight>>? highlights; // 상세 화면: 핵심 내용마다 용어 하이라이트

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s14, children: [
      for (final (i, p) in news.keyPoints.indexed)
        // 번호는 본문과 같은 15pt, 간격 8(S02 핵심 내용과 같다)
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s8, children: [
          Text('${i + 1}', style: RgText.bodySummary.copyWith(fontWeight: FontWeight.w700)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TermText(p.text, highlights: highlights?.elementAtOrNull(i) ?? const [], style: RgText.bodySummary),
              if (p.para != null)
                Semantics(
                  link: true,
                  label: '근거, ${_evidence(p)}',
                  excludeSemantics: true,
                  onTap: () => _open(news.evidenceUrl(p)),
                  child: RgPressable(
                    onTap: () => _open(news.evidenceUrl(p)),
                    child: EvidencePill(label: '근거 · ${_evidence(p)}'),
                  ),
                ),
            ]),
          ),
        ]),
    ]);
  }

  // OpenAI 글은 피드 소개문이 근거다
  String _evidence(NewsPoint p) => news.source == 'openai' ? '원문 소개문' : '원문 ${p.para}번째 문단';

  void _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

// 근거 알약(핵심 내용 아래): 인용 아이콘 + 「근거 · 초록 2번째 문장」. 보이는 높이 30, 누르는 높이 44.
class EvidencePill extends StatelessWidget {
  const EvidencePill({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: RgSpace.minTouch),
    alignment: Alignment.centerLeft,
    child: Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: RgSpace.s10, vertical: RgSpace.s6),
      decoration: BoxDecoration(color: RgColors.fillNeutral, borderRadius: BorderRadius.circular(RgRadius.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: RgSpace.s4, children: [
        RgIcon('quote', size: 14, color: RgColors.textBody),
        Flexible(child: Text(label, style: RgText.caption.copyWith(height: 1.25, fontWeight: FontWeight.w500, color: RgColors.textBody))),
      ]),
    ),
  );
}

// 「지난번에 여기까지 봤어요」 선: 새 글 색의 가는 선 + 가운데 글자. 화면 안에서는 움직이지 않는다(다음에 열 때만 옮겨 간다).
class _ReadLine extends StatelessWidget {
  const _ReadLine();

  @override
  Widget build(BuildContext context) {
    final line = Expanded(child: Container(height: 1, color: RgColors.newText.withValues(alpha: 0.3)));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s8),
      child: Row(spacing: RgSpace.s8, children: [
        line,
        Text('지난번에 여기까지 봤어요', style: RgText.caption.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: RgColors.newText)),
        line,
      ]),
    );
  }
}
