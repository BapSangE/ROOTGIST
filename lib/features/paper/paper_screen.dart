import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_card.dart';
import '../../design/widgets/rg_pressable.dart';
import 'evidence_sheet.dart';

// S02 논문 상세 (HANDOFF 7.2). ready가 아닐 때의 준비 중·오류 카드와 로딩 스켈레톤은 M3.
class PaperScreen extends StatefulWidget {
  const PaperScreen({super.key, required this.paperId});
  final String paperId;

  @override
  State<PaperScreen> createState() => _PaperScreenState();
}

class _PaperScreenState extends State<PaperScreen> {
  late final _paper = repository.getPaper(widget.paperId);

  @override
  Widget build(BuildContext context) {
    final bottom = math.max(RgSpace.floatingBottom, MediaQuery.paddingOf(context).bottom);
    return Scaffold(
      body: FutureBuilder(
        future: _paper,
        builder: (context, snap) {
          final p = snap.data;
          return Stack(children: [
            Positioned.fill(
              child: ListView(
                padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, bottom: RgSpace.bottomScrollInset),
                children: [
                  _TopBar(paper: p),
                  if (p != null) ..._content(context, p),
                ],
              ),
            ),
            if (p != null && p.ready)
              Positioned(
                left: RgSpace.gutterCard,
                right: RgSpace.gutterCard,
                bottom: bottom,
                child: RgPrimaryButton(
                  label: '번역과 함께 초록 읽기',
                  floating: true,
                  onTap: () => context.push('/paper/${p.id}/reader'),
                ),
              ),
          ]);
        },
      ),
    );
  }

  List<Widget> _content(BuildContext context, PaperDetail p) {
    final secondary = RgText.meta.copyWith(color: RgColors.textSecondary);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s12, RgSpace.gutterText, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (p.topicLabel != null) ...[RgBadge(label: p.topicLabel!, onCard: false), const SizedBox(height: RgSpace.s14)],
            Semantics(header: true, child: Text(keepAll(p.title), style: RgText.titleDetail)),
            if (p.ready && p.titleKo != null) ...[
              const SizedBox(height: RgSpace.s8),
              Text(p.titleEn, style: RgText.serifSubtitle.copyWith(color: RgColors.textBody)),
            ],
            const SizedBox(height: RgSpace.s10),
            Text('${p.authorLine} · ${p.date} 발행', style: secondary),
          ],
        ),
      ),
      if (p.ready) ...[
        const SizedBox(height: RgSpace.s24),
        RgCard(
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text('AI 요약', style: RgText.titleCard)),
              const SizedBox(height: RgSpace.s8),
              Text(keepAll(p.summary ?? ''), style: RgText.bodySummary.copyWith(color: RgColors.textBody)),
              if (p.keyPoints.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: RgSpace.s16),
                  child: Divider(height: 1, thickness: 1, color: RgColors.dividerCard),
                ),
                Semantics(header: true, child: Text('핵심 내용', style: RgText.titleCard)),
                const SizedBox(height: RgSpace.s10),
                Column(
                  spacing: RgSpace.s14,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, k) in p.keyPoints.take(3).indexed) _KeyPointItem(paper: p, index: i + 1, point: k),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: RgSpace.s12),
        // ponytail: 탭 → C03은 C03을 만들 때 연결한다.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: RgSpace.s6,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1.5),
                child: RgIcon('info', size: 14, color: RgColors.textSecondary),
              ),
              Expanded(
                child: Text(
                  keepAll('초록을 바탕으로 AI가 정리했어요. 논문 본문 전체를 반영하지는 않아요.'),
                  style: RgText.caption.copyWith(height: 17 / 12, color: RgColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: RgSpace.s28),
      RgCard(
        padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s4),
        child: Column(children: [
          _InfoRow(
            label: '원문 출처',
            value: 'arXiv · ${p.id}',
            onTap: () => launchUrl(Uri.parse(p.arxivUrl), mode: LaunchMode.externalApplication),
          ),
          if (p.orgName != null) _InfoRow(label: '게시 조직', value: p.orgName!), // G8
          _InfoRow(label: '발행일', value: p.date, last: true),
        ]),
      ),
    ];
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.paper});
  final PaperDetail? paper;

  @override
  Widget build(BuildContext context) {
    final p = paper;
    return SizedBox(
      height: RgSpace.topBar,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
        child: Row(spacing: RgSpace.s8, children: [
          RgCircleButton(semanticLabel: '뒤로', icon: 'chevron-left', onTap: () => context.pop()),
          const Spacer(),
          if (p != null) ...[
            RgCircleButton(
              semanticLabel: '공유',
              icon: 'share',
              onTap: () => SharePlus.instance.share(ShareParams(text: '${p.title}\n${p.hfUrl}')),
            ),
            ValueListenableBuilder(
              valueListenable: bookmarks,
              builder: (_, saved, _) => RgBookmarkButton(saved: saved.containsKey(p.id), onTap: () => toggleBookmark(p.id, p.title)),
            ),
          ],
        ]),
      ),
    );
  }
}

class _KeyPointItem extends StatelessWidget {
  const _KeyPointItem({required this.paper, required this.index, required this.point});
  final PaperDetail paper;
  final int index;
  final KeyPoint point;

  @override
  Widget build(BuildContext context) {
    final n = sentenceNumber(point.evidenceIds.first);
    final linkStyle = RgText.meta.copyWith(color: RgColors.textSecondary);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: RgSpace.s12,
      children: [
        Text('$index', style: RgText.meta.copyWith(height: 23 / 13, fontWeight: FontWeight.w600, color: RgColors.textTertiary)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(keepAll(point.claim), style: RgText.bodySummary),
              Semantics(
                button: true,
                label: '원문 근거, 초록 $n번째 문장',
                excludeSemantics: true,
                child: RgPressable(
                  onTap: () => showEvidenceSheet(context, paper: paper, pointIndex: index, sentenceId: point.evidenceIds.first),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 36),
                    child: Row(mainAxisSize: MainAxisSize.min, spacing: RgSpace.s2, children: [
                      Text('원문 근거 · 초록 $n번째 문장', style: linkStyle),
                      const RgIcon('chevron-right', size: 14, color: RgColors.textSecondary),
                    ]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.onTap, this.last = false});
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: RgSpace.s14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: RgSpace.s16,
        children: [
          Text(label, style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
          Expanded(child: Text(value, textAlign: TextAlign.end, style: RgText.bodySmall)),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: RgColors.dividerCard)),
      ),
      child: onTap == null ? row : Semantics(link: true, child: RgPressable(onTap: onTap, child: row)),
    );
  }
}
