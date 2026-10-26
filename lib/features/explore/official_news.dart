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
import '../../design/widgets/rg_segmented.dart';
import '../../design/widgets/rg_states.dart';
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
  var _updates = exploreJump.value?.updates ?? false; // false = 발표, true = 업데이트
  String? _source; // null = 전체

  // 홈 「업데이트 더 보기」로 들어오면 업데이트를, 「공식 발표 더 보기」면 발표를 고른다
  void _jump() {
    final j = exploreJump.value;
    if (j != null && j.tab == 1 && mounted) {
      setState(() {
        _updates = j.updates;
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
            const SizedBox(height: RgSpace.s16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
              child: RgSegmented(
                options: const [(false, '발표'), (true, '업데이트')],
                value: _updates,
                onChanged: (v) => setState(() {
                  _updates = v;
                  _source = null;
                }),
              ),
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
      const SizedBox(height: RgSpace.s12),
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
              style: RgText.caption.copyWith(color: RgColors.textSecondary),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(newsMeta(n), style: RgText.caption.copyWith(color: RgColors.textSecondary)),
        const SizedBox(height: RgSpace.s4),
        KeepAllText(n.titleKo ?? n.titleEn, style: RgText.titleList),
      ]),
    );
  }
}

ItemActions newsActions(OfficialNews n, {RgCircleVariant variant = RgCircleVariant.plain}) =>
    ItemActions(id: n.id, title: n.titleKo ?? n.titleEn, url: n.url, source: n.sourceLabel, kind: 'news', variant: variant);

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.news});
  final OfficialNews news;

  @override
  Widget build(BuildContext context) {
    final meta = newsMeta(news);
    final linkStyle = RgText.meta.copyWith(color: RgColors.textSecondary);
    final release = news.kind == 'release';
    return RgCard(
      padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 머리(출처·제목)는 누르면 원문으로. 오른쪽 위에 공유·북마크
        Semantics(
          link: true,
          label: '$meta, ${news.titleKo ?? news.titleEn}, 원문 열기',
          excludeSemantics: true,
          onTap: () => _open(news.url),
          child: RgPressable(
            onTap: () => _open(news.url),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s8, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(meta, style: RgText.caption.copyWith(color: RgColors.textSecondary)),
                  const SizedBox(height: RgSpace.s4),
                  KeepAllText(news.titleKo ?? news.titleEn, style: RgText.titleList),
                  if (news.titleKo != null && !release) ...[
                    const SizedBox(height: RgSpace.s4),
                    Text(news.titleEn, style: linkStyle),
                  ],
                ]),
              ),
              // 누르는 영역 44는 그대로 두고 모양만 카드 모서리 쪽으로(추천 카드와 같게)
              Transform.translate(offset: const Offset(RgSpace.s12, -RgSpace.s10), child: newsActions(news)),
            ]),
          ),
        ),
        if (news.summaryKo case final s?) ...[
          const SizedBox(height: RgSpace.s12),
          KeepAllText(s, style: RgText.bodySummary.copyWith(color: RgColors.textBody)),
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
    final linkStyle = RgText.meta.copyWith(color: RgColors.textSecondary);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s10, children: [
      for (final (i, p) in news.keyPoints.indexed)
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s10, children: [
          Text('${i + 1}', style: RgText.meta.copyWith(height: 23 / 13, fontWeight: FontWeight.w600, color: RgColors.textTertiary)),
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
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 36),
                      child: Row(mainAxisSize: MainAxisSize.min, spacing: RgSpace.s2, children: [
                        Flexible(child: Text('근거 · ${_evidence(p)}', style: linkStyle)),
                        const RgIcon('chevron-right', size: 14, color: RgColors.textSecondary),
                      ]),
                    ),
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
