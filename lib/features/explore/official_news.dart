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
import '../../design/widgets/rg_underline_tabs.dart';
import '../../design/widgets/rg_states.dart';
import '../../data/unread.dart';
import '../../design/widgets/rg_new_dot.dart';
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
  late var _updates = newsUpdates.value = exploreJump.value?.updates ?? false; // false = 발표, true = 업데이트
  String? _source; // null = 전체

  // 홈 「업데이트 더 보기」로 들어오면 업데이트를, 「공식 발표 더 보기」면 발표를 고른다
  void _jump() {
    final j = exploreJump.value;
    if (j != null && j.tab == 1 && mounted) {
      setState(() {
        _updates = newsUpdates.value = j.updates;
        _source = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    exploreJump.addListener(_jump);
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
              labels: const ['발표', '업데이트'],
              selected: _updates ? 1 : 0,
              onTap: (i) => setState(() {
                _updates = newsUpdates.value = i == 1;
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
    final kind = [for (final n in all) if (n.isUpdate == _updates) n];
    if (kind.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s24, RgSpace.gutterText, 0),
          child: KeepAllText('아직 모은 소식이 없어요', style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
        ),
      ];
    }
    // 칩은 이름순으로 고정(글 순서대로면 날마다 칩 자리가 바뀐다)
    final sources = {for (final n in kind) n.source: n.sourceLabel}.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    final shown = [for (final n in kind) if (_source == null || n.source == _source) n];
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
      if (_updates)
        for (final n in shown) ...[const SizedBox(height: RgSpace.s12), _NewsCard(news: n)]
      else ...[
        const SizedBox(height: RgSpace.s12),
        RgCard(child: Column(children: [for (final (i, n) in shown.indexed) NewsRow(news: n, last: i == shown.length - 1)])),
      ],
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
}

// 발표 한 줄(탐색 목록, 홈 하이라이트): 출처·날짜 + 제목, 누르면 상세. 오른쪽에 공유·북마크.
class NewsRow extends StatelessWidget {
  const NewsRow({super.key, required this.news, required this.last});
  final OfficialNews news;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final n = news;
    return RgListRow(
      showDivider: !last,
      onTap: () => context.push('/news/${Uri.encodeComponent(n.id)}'),
      trailing: newsActions(n),
      // 왼쪽 출처 머리글자 배지(피드백 3차 A안: 묶음마다 모양을 다르게)
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s12, children: [
        SourceBadge(news: n),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            NewsMetaLine(news: n),
            const SizedBox(height: RgSpace.s4),
            KeepAllText(n.titleKo ?? n.titleEn, style: RgText.titleList),
            if (n.thin) ...[
              const SizedBox(height: RgSpace.s8),
              const RgTag(label: '원문 소개문만'),
            ],
          ]),
        ),
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
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s12, children: [
        SourceBadge(news: n),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(newsMeta(n), style: RgText.meta.copyWith(color: RgColors.textSecondary)),
            const SizedBox(height: RgSpace.s2),
            KeepAllText(n.titleKo ?? n.titleEn, style: RgText.titleList),
            if (hint != null) ...[
              const SizedBox(height: RgSpace.s4),
              KeepAllText(hint, style: RgText.bodySmall.copyWith(color: RgColors.textBody)),
            ],
          ]),
        ),
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

// 출처 머리글자 배지 34×34(모서리 10). 로고 대신 Pretendard 머리글자 + 회사 대표 색 한 가지(RgBrand).
// 로고·이미지는 쓰지 않는다(docs/RIGHTS.md 4장). 대표 색이 없는 출처는 fill 회색.
class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.news, this.size = 34});
  final OfficialNews news;
  final double size;

  static const _initials = {
    'openai': 'OA',
    'openai_community': 'OA',
    'anthropic': 'An',
    'deepmind': 'GD',
    'google_research': 'GR',
    'huggingface': 'HF',
    'claude_code': 'CC',
    'claude_api': 'CA',
  };

  // (바탕, 글자). 같은 회사는 같은 색
  static const _colors = {
    'anthropic': (RgBrand.anthropic, RgColors.onAction),
    'claude_code': (RgBrand.anthropic, RgColors.onAction),
    'claude_api': (RgBrand.anthropic, RgColors.onAction),
    'openai': (RgBrand.openai, RgColors.onAction),
    'openai_community': (RgBrand.openai, RgColors.onAction),
    'deepmind': (RgBrand.google, RgColors.onAction),
    'google_research': (RgBrand.google, RgColors.onAction),
    'huggingface': (RgBrand.huggingface, RgColors.textPrimary),
  };

  @override
  Widget build(BuildContext context) {
    final c = _colors[news.source];
    return RgSquareBadge(
      text: _initials[news.source] ?? news.sourceLabel.substring(0, 2),
      size: size,
      color: c?.$1,
      textColor: c?.$2,
    );
  }
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
          onTap: () => context.push('/news/${Uri.encodeComponent(n.id)}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(RgSpace.s20, RgSpace.s18, RgSpace.s8, RgSpace.s18),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s8, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  NewsMetaLine(news: n),
                  const SizedBox(height: RgSpace.s6),
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

// 홈 「이번 주 바뀐 도구」 한 줄(피드백 3차 A안): 도구 이름 + 날짜, 오른쪽에 버전 태그. 누르면 상세.
class UpdateRow extends StatelessWidget {
  const UpdateRow({super.key, required this.news, required this.last});
  final OfficialNews news;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final n = news;
    final release = n.kind == 'release';
    final k = n.publishedAt.toUtc().add(const Duration(hours: 9));
    return RgListRow(
      showDivider: !last,
      crossAxisAlignment: CrossAxisAlignment.center,
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      onTap: () => context.push('/news/${Uri.encodeComponent(n.id)}'),
      // 태그는 trailing이 아니라 같은 줄의 Flexible: 큰 글자에서 「v2.1.310 · 7건」이 길어지면 줄을 바꿔 들어간다
      // 이름 3 : 태그 2. 태그는 제 칸 안에서 오른쪽 끝에(Flexible만 쓰면 칸 가운데부터 놓였다)
      child: Row(spacing: RgSpace.s8, children: [
        Padding(padding: const EdgeInsets.only(right: RgSpace.s4), child: SourceBadge(news: n)),
        Expanded(
          flex: 3,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            KeepAllText(release ? n.sourceLabel : (n.titleKo ?? n.titleEn), style: RgText.titleList),
            const SizedBox(height: RgSpace.s2),
            Text(
              [if (!release) n.sourceLabel, '${k.month}월 ${k.day}일'].join(' · '),
              style: RgText.meta.copyWith(color: RgColors.textSecondary),
            ),
          ]),
        ),
        Flexible(
          flex: 2,
          child: Align(
            alignment: Alignment.centerRight,
            child: RgTag(label: keepAll(releaseTag(n))),
          ),
        ),
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

// 출처·날짜 줄. 안 연 새 글이면 앞에 점(unread.dart)
class NewsMetaLine extends StatelessWidget {
  const NewsMetaLine({super.key, required this.news});
  final OfficialNews news;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: readItems,
    // 새 글은 출처 줄 끝에 「새 글」 글자. 출처 배지가 회사 색을 쓰게 되면서, 점(색)만으로는 배지 색과 신호가 섞였다.
    builder: (context, _, _) => Row(spacing: RgSpace.s6, children: [
      Flexible(child: Text(newsMeta(news), style: RgText.caption.copyWith(color: RgColors.textSecondary))),
      if (isNew(newsKey(news), news.publishedAt)) const RgNewLabel(),
    ]),
  );
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
        onTap: () => context.push('/news/${Uri.encodeComponent(news.id)}'),
        child: RgCard(
      padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 머리(출처·제목). 오른쪽 위에 공유·북마크
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s8, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  NewsMetaLine(news: news),
                  const SizedBox(height: RgSpace.s4),
                  KeepAllText(news.titleKo ?? news.titleEn, style: RgText.titleList),
                  if (news.titleKo != null && !release) ...[
                    const SizedBox(height: RgSpace.s4),
                    Text(news.titleEn, style: linkStyle),
                  ],
                ]),
              ),
              // 누르는 영역 44는 그대로 두고 모양만 카드 모서리 쪽으로(추천 카드와 같게)
              // 업데이트 카드는 목록에서 바로 공유도
              Transform.translate(offset: const Offset(RgSpace.s12, -RgSpace.s10), child: newsActions(news, share: true)),
            ]),
        if (news.summaryKo case final s?) ...[
          const SizedBox(height: RgSpace.s12),
          KeepAllText(s, perSentence: true, style: RgText.bodySummary.copyWith(color: RgColors.textBody)),
        ],
        if (news.keyPoints.isNotEmpty) ...[const SizedBox(height: RgSpace.s12), NewsPoints(news: news)],
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
}

String newsMeta(OfficialNews n) {
  final k = n.publishedAt.toUtc().add(const Duration(hours: 9));
  return [n.sourceLabel, ?n.categoryKo, '${k.month}월 ${k.day}일'].join(' · ');
}

// 번호 붙은 핵심 내용. 근거가 있으면 「근거 · 원문 N번째 문단 ›」 → 원문의 그 구절 위치로.
class NewsPoints extends StatelessWidget {
  const NewsPoints({super.key, required this.news});
  final OfficialNews news;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s14, children: [
      for (final (i, p) in news.keyPoints.indexed)
        // 번호는 본문과 같은 15pt, 간격 8(S02 핵심 내용과 같다)
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s8, children: [
          Text('${i + 1}', style: RgText.bodySummary.copyWith(fontWeight: FontWeight.w700)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              KeepAllText(p.text, style: RgText.bodySummary),
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
