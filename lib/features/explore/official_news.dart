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

  // 홈 「업데이트 더 보기」로 들어오면 업데이트를, 「공식 발표 더 보기」면 발표를 고른다
  void _jump() {
    final j = exploreJump.value;
    if (j != null && j.tab == 1 && mounted) {
      setState(() {
        _tab = newsTab.value = j.newsTab;
        _source = null;
      });
    }
  }

  // 「여기까지 봤어요」: 이 화면을 열기 전 값(이번에 연 뒤에는 맨 위 글 시각으로 바꾼다)
  final DateTime? _seenBefore = newsSeenAt.value;

  // 날짜 머리별로 나눈다(받은 순서 = 최신순 유지)
  List<(String, List<OfficialNews>)> _byDay(List<OfficialNews> list, DateTime now) {
    final out = <(String, List<OfficialNews>)>[];
    for (final n in list) {
      final day = dayHeaderKo(n.publishedAt, now);
      if (out.isNotEmpty && out.last.$1 == day) {
        out.last.$2.add(n);
      } else {
        out.add((day, [n]));
      }
    }
    return out;
  }

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
              labels: const ['발표', '업데이트', '화제'],
              selected: _tab,
              onTap: (i) => setState(() {
                _tab = newsTab.value = i;
                _source = null;
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
      // 발표는 논문 목록처럼 짧은 행, 누르면 상세(실기기 QA: 한 화면이 너무 길었다). 업데이트는 4~5개라 카드 그대로.
      // 발표·업데이트나 출처 칩을 바꾸면 목록이 떠오르며 바뀐다(RgFilterSwitch)
      RgFilterSwitch(
        switchKey: (_tab, _source),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_updates)
            for (final n in shown) ...[const SizedBox(height: RgSpace.s12), _NewsCard(news: n)]
          else
            // 날짜 머리(오늘·어제·날짜)마다 카드 하나. 지난번에 본 맨 위 글 앞에 「여기까지 봤어요」 선
            for (final (day, rows) in _byDay(shown, now)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s20, RgSpace.gutterText, RgSpace.s8),
                child: Semantics(header: true, child: Text(day, style: RgText.meta.copyWith(fontWeight: FontWeight.w700, color: RgColors.textSecondary))),
              ),
              RgCard(
                child: Column(children: [
                  for (final (i, n) in rows.indexed) ...[
                    if (_seenBefore case final seen? when n.publishedAt.compareTo(seen) <= 0 && shown.first.publishedAt.isAfter(seen) && _firstSeen(shown) == n)
                      const _ReadLine(),
                    NewsRow(news: n, last: i == rows.length - 1, summary: true),
                  ],
                ]),
              ),
            ],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s12, RgSpace.gutterText, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s6, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: RgIcon('info', size: 14, color: RgColors.textSecondary)),
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

  // 화제 칸(시안 B): Hacker News(최근 24시간, 점수 순) → GitHub 이번 주 새 AI 도구(별 순). 칩 거르기 없음
  List<Widget> _hotList(BuildContext context, List<OfficialNews> all) {
    final now = clock();
    final hn = [for (final n in all) if (n.isHot && !n.isGithub && now.difference(n.publishedAt).inHours < 48) n]
      ..sort((a, b) => (b.points ?? 0).compareTo(a.points ?? 0));
    final gh = [for (final n in all) if (n.isGithub) n]..sort((a, b) => (b.points ?? 0).compareTo(a.points ?? 0));
    Widget group(String title, List<OfficialNews> rows) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s20, RgSpace.gutterText, RgSpace.s8),
        child: Semantics(header: true, child: Text(title, style: RgText.meta.copyWith(fontWeight: FontWeight.w700, color: RgColors.textSecondary))),
      ),
      RgCard(child: Column(children: [for (final (i, n) in rows.indexed) NewsRow(news: n, last: i == rows.length - 1, summary: true)])),
    ]);
    return [
      RgFilterSwitch(
        switchKey: _tab,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (hn.isEmpty && gh.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s24, RgSpace.gutterText, 0),
              child: KeepAllText('아직 모은 화제가 없어요', style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
            ),
          if (hn.isNotEmpty) group('Hacker News · 최근 이틀', hn),
          if (gh.isNotEmpty) group('GitHub · 이번 주 새 AI 도구', gh),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s12, RgSpace.gutterText, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s6, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: RgIcon('info', size: 14, color: RgColors.textSecondary)),
          Expanded(
            child: KeepAllText(
              '개발자들이 많이 본 글과 새 도구예요. 공식 발표가 아니라 각 사이트의 글이고, 점수는 Hacker News 추천 수·GitHub 별 수예요. 요약은 원문 사이트가 허용할 때만 AI가 만들어요.',
              perSentence: true, style: RgText.caption.copyWith(color: RgColors.textSecondary),
            ),
          ),
        ]),
      ),
    ];
  }
}

// 발표 한 줄(탐색 목록, 홈 하이라이트): 머리 줄(출처 칩 · 분류 · 날짜 · 새 글) + 제목, 누르면 상세. 오른쪽에 북마크.
class NewsRow extends StatelessWidget {
  const NewsRow({super.key, required this.news, required this.last, this.summary = false});
  final OfficialNews news;
  final bool last;
  final bool summary; // 탐색 발표 목록: 제목 아래 두 줄 요약

  @override
  Widget build(BuildContext context) {
    final n = news;
    return RgListRow(
      showDivider: !last,
      onTap: () => context.push('/news/${Uri.encodeComponent(n.id)}'),
      trailing: newsActions(n),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        NewsHead(news: n),
        const SizedBox(height: RgSpace.s6),
        KeepAllText(n.titleKo ?? n.titleEn, style: RgText.titleList),
        // 두 줄 요약(시안 C): 목록만 훑어도 무슨 소식인지. 요약·핵심 내용·근거 전체는 상세에서
        if ((summary ? (n.summaryKo ?? n.keyPoints.firstOrNull?.text) : null) case final s?) ...[
          const SizedBox(height: RgSpace.s4),
          KeepAllText(s, maxLines: 2, overflow: TextOverflow.ellipsis, style: RgText.bodySmall.copyWith(color: RgColors.textBody)),
        ],
        if (n.thin && !n.isHot) ...[
          const SizedBox(height: RgSpace.s8),
          const RgTag(label: '원문 소개문만'),
        ],
      ]),
    );
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
      trailing: const Padding(
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

// 공식 소식 머리 줄: 출처 이름 칩(회사 대표 색) · 분류 · 날짜 · 「새 글」. 출처 칩은 로고 대신 이름 글자만(docs/RIGHTS.md 4장).
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
              : [?news.categoryKo, relativeKo(news.publishedAt, clock()), ?news.reaction].join(' · '),
      isNew: isNew(newsKey(news), news.publishedAt),
    ),
  );
}

// 홈 「연구소 소식」 맨 위 대표 글(피드백 3차 C안): 출처 줄 → 제목(카드 제목 크기) → 요약 두 줄까지. 오른쪽 위 북마크.
class FeaturedNews extends StatelessWidget {
  const FeaturedNews({super.key, required this.news, required this.divider});
  final OfficialNews news;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final n = news;
    return DecoratedBox(
      decoration: BoxDecoration(border: divider ? Border(bottom: BorderSide(color: RgColors.dividerCard)) : null),
      child: Semantics(
        button: true,
        child: RgPressable(
          row: true,
          onTap: () => context.push('/news/${Uri.encodeComponent(n.id)}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(RgSpace.s20, RgSpace.s18, RgSpace.s8, RgSpace.s18),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s8, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  NewsHead(news: n),
                  const SizedBox(height: RgSpace.s8),
                  KeepAllText(n.titleKo ?? n.titleEn, style: RgText.titleCard),
                  if (n.summaryKo case final s?) ...[
                    const SizedBox(height: RgSpace.s6),
                    KeepAllText(s, maxLines: 2, overflow: TextOverflow.ellipsis, style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
                  ],
                ]),
              ),
              newsActions(n),
            ]),
          ),
        ),
      ),
    );
  }
}

// 홈 「이번 주 바뀐 도구」 한 줄: 머리 줄(출처 칩 · 버전·건수 · 날짜 · 새 글) + 제목. 누르면 상세. 오른쪽에 북마크.
// 공지는 버전 대신 「공지」. 다른 목록 행과 같은 모양(통일 행 구조).
class UpdateRow extends StatelessWidget {
  const UpdateRow({super.key, required this.news, required this.last});
  final OfficialNews news;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final n = news;
    return RgListRow(
      showDivider: !last,
      onTap: () => context.push('/news/${Uri.encodeComponent(n.id)}'),
      trailing: newsActions(n),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        NewsHead(news: n, release: true),
        const SizedBox(height: RgSpace.s6),
        KeepAllText(n.titleKo ?? n.titleEn, style: RgText.titleList),
      ]),
    );
  }
}

// 「v2.1.310 · 7건」. 원제(수집기가 만든 「Claude Code v2.1.304~v2.1.310 (7 releases)」)에서 마지막 버전과 건수를 꺼낸다.
// 버전이 없으면 건수만(「19건」), 공지는 「공지」.
String releaseTag(OfficialNews n) {
  if (n.kind != 'release') return '공지';
  final ver = RegExp(r'v[\d.]+(?:~(v[\d.]+))?').firstMatch(n.titleEn);
  final count = RegExp(r'\((\d+) (?:releases?|changes?)\)').firstMatch(n.titleEn)?.group(1);
  final last = ver == null ? null : (ver.group(1) ?? ver.group(0));
  return [?last, if (count != null) '$count건'].join(' · ');
}

String newsKey(OfficialNews n) => 'news:${n.id}';
bool hasNewNews(Iterable<OfficialNews> news) => news.any((n) => isNew(newsKey(n), n.publishedAt));

ItemActions newsActions(OfficialNews n, {RgCircleVariant variant = RgCircleVariant.neutral, bool share = false}) => ItemActions(
  id: n.id,
  title: n.titleKo ?? n.titleEn,
  url: n.url,
  source: n.sourceLabel,
  kind: 'news',
  variant: variant,
  share: share,
);

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.news});
  final OfficialNews news;

  @override
  Widget build(BuildContext context) {
    final linkStyle = RgText.meta.copyWith(color: RgColors.textSecondary);
    final release = news.kind == 'release';
    // 카드 어디를 눌러도 소식 상세로(홈 「이번 주 바뀐 도구」와 같다). 상세가 열리면 새 글 점이 지워진다.
    // 실기기 QA: 머리만 원문으로 열려 본문을 누르면 반응이 없었고, 원문을 열지 않으면 점이 남았다.
    // 근거·릴리스 노트 링크와 공유·북마크는 제 동작이 먼저다.
    return Semantics(
      button: true,
      child: RgPressable(
        row: true,
        onTap: () => context.push('/news/${Uri.encodeComponent(news.id)}'),
        child: RgCard(
      padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 머리(출처·제목). 오른쪽 위에 공유·북마크
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s8, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  NewsHead(news: news),
                  const SizedBox(height: RgSpace.s6),
                  KeepAllText(news.titleKo ?? news.titleEn, style: RgText.titleList),
                  if (news.titleKo != null && !news.isUpdate) ...[ // 업데이트는 간추려 원제도 뺀다(상세에 있다)
                    const SizedBox(height: RgSpace.s4),
                    Text(news.titleEn, style: linkStyle),
                  ],
                ]),
              ),
              // 누르는 영역 44는 그대로 두고 모양만 카드 모서리 쪽으로(추천 카드와 같게)
              // 업데이트 카드는 목록에서 바로 공유도
              Transform.translate(offset: const Offset(RgSpace.s12, -RgSpace.s10), child: newsActions(news, share: true)),
            ]),
        // 업데이트(공지·릴리스)는 목록에서 간추려 보인다: 공지는 요약 두 줄, 릴리스는 주요 변경 두 개(각 두 줄).
        // 요약·핵심 내용 전체와 근거는 눌러서 여는 상세에서(실기기 QA: 목록과 상세가 같은 내용을 되풀이했다).
        if (news.isUpdate)
          ..._brief(news)
        else ...[
          if (news.summaryKo case final s?) ...[
            const SizedBox(height: RgSpace.s12),
            KeepAllText(s, perSentence: true, style: RgText.bodySummary.copyWith(color: RgColors.textBody)),
          ],
          if (news.keyPoints.isNotEmpty) ...[const SizedBox(height: RgSpace.s12), NewsPoints(news: news)],
        ],
        if (release) ...[
          const SizedBox(height: RgSpace.s6),
          Semantics(
            link: true,
            child: RgPressable(
              onTap: () => _open(news.url),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: Row(mainAxisSize: MainAxisSize.min, spacing: RgSpace.s2, children: [
                  Text('릴리스 노트 전체 보기', style: linkStyle),
                  const RgIcon('arrow-up-right', size: 14, color: RgColors.textSecondary),
                ]),
              ),
            ),
          ),
        ],
      ]),
        ),
      ),
    );
  }

  void _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  List<Widget> _brief(OfficialNews n) {
    final body = RgText.bodySmall.copyWith(color: RgColors.textBody);
    final more = RgText.meta.copyWith(color: RgColors.textSecondary);
    if (n.summaryKo case final s? when n.kind != 'release') {
      return [
        const SizedBox(height: RgSpace.s10),
        KeepAllText(s, maxLines: 2, overflow: TextOverflow.ellipsis, style: body),
      ];
    }
    final shown = n.keyPoints.take(2).toList();
    if (shown.isEmpty) return const [];
    return [
      const SizedBox(height: RgSpace.s10),
      for (final p in shown)
        Padding(
          padding: const EdgeInsets.only(bottom: RgSpace.s4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s8, children: [
            Padding(
              padding: EdgeInsets.only(top: (body.fontSize! * body.height! - 4) / 2),
              child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: RgColors.textTertiary, shape: BoxShape.circle)),
            ),
            Expanded(child: KeepAllText(p.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: body)),
          ]),
        ),
      if (n.keyPoints.length > shown.length) Text('외 ${n.keyPoints.length - shown.length}개 · 눌러서 모두 보기', style: more),
    ];
  }
}

String newsMeta(OfficialNews n) => [n.sourceLabel, ?n.categoryKo, newsDate(n)].join(' · ');

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
        const RgIcon('quote', size: 14, color: RgColors.textBody),
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
