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
import '../../design/widgets/rg_states.dart';
import '../reader/text_size_sheet.dart';
import '../settings/ai_notice_sheet.dart';
import 'evidence_sheet.dart';

// S02 논문 상세 (HANDOFF 7.2). 8.1 상태: 로딩 스켈레톤, 오류(보관함 제목이 있으면 제목 블록만 남김),
// ai_status가 ready가 아니면 제목 블록 + 준비 중/실패 카드(4.3).
class PaperScreen extends StatefulWidget {
  const PaperScreen({super.key, required this.paperId});
  final String paperId;

  @override
  State<PaperScreen> createState() => _PaperScreenState();
}

class _PaperScreenState extends State<PaperScreen> {
  late final _req = Reloadable(() => repository.getPaper(widget.paperId));

  @override
  void dispose() {
    _req.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = math.max(RgSpace.floatingBottom, MediaQuery.paddingOf(context).bottom);
    return Scaffold(
      body: ListenableBuilder(
        listenable: _req,
        builder: (context, _) => FutureBuilder(
          future: _req.future,
          builder: (context, snap) {
            final p = snap.data;
            final savedTitle = bookmarks.value[widget.paperId]?.title; // 7.7 오프라인에서 보관함으로 들어온 경우
            return Stack(
              children: [
                Positioned.fill(
                  child: ListView(
                    padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, bottom: RgSpace.bottomScrollInset),
                    children: [
                      _TopBar(paper: p),
                      if (p != null)
                        ..._content(context, p)
                      else if (snap.hasError) ...[
                        if (savedTitle != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s12, RgSpace.gutterText, 0),
                            child: HeadingTextScale(child: Semantics(header: true, child: KeepAllText(savedTitle, style: RgText.titleDetail))),
                          ),
                        const SizedBox(height: RgSpace.s24),
                        RgErrorCard(error: snap.error, onRetry: _req.reload),
                      ] else
                        const _PaperSkeleton(),
                    ],
                  ),
                ),
                // 상태바 밑 배경색 띠(쉘과 같은 이유)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: MediaQuery.paddingOf(context).top,
                  child: const ColoredBox(color: RgColors.bgApp),
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
              ],
            );
          },
        ),
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
            if (p.topicLabel != null) ...[
              RgBadge(label: p.topicLabel!, onCard: false),
              const SizedBox(height: RgSpace.s14),
            ],
            HeadingTextScale(child: Semantics(header: true, child: KeepAllText(p.title, style: RgText.titleDetail))),
            if (p.ready && p.titleKo != null) ...[
              const SizedBox(height: RgSpace.s8),
              Text(p.titleEn, style: RgText.serifSubtitle.copyWith(color: RgColors.textBody)),
            ],
            const SizedBox(height: RgSpace.s10),
            KeepAllText('${p.authorLine} · ${p.date} 발행', style: secondary),
          ],
        ),
      ),
      if (!p.ready) ...[
        const SizedBox(height: RgSpace.s24),
        RgCard(
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.aiStatus == 'failed' ? '해설을 만들지 못했어요' : '해설을 준비하고 있어요', style: RgText.titleCard),
              const SizedBox(height: RgSpace.s6),
              Text('다음 수집 때 다시 만들어요. 원문은 아래 링크에서 볼 수 있어요.', style: secondary),
            ],
          ),
        ),
      ],
      if (p.ready) ...[
        const SizedBox(height: RgSpace.s24),
        // 설정의 글자 크기 4단계가 S03 본문과 함께 이 카드에도 적용된다(iOS QA).
        ReaderTextScale(
          child: RgCard(
            padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, child: Text('AI 요약', style: RgText.titleCard)),
                const SizedBox(height: RgSpace.s8),
                // G4: 전문은 그대로 보이되, 실제 요약은 15줄 안팎 한 덩어리라 문장마다 문단을 나눈다.
                Column(
                  spacing: RgSpace.s8,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in summaryParagraphs(p.summary ?? ''))
                      KeepAllText(s, style: RgText.bodySummary.copyWith(color: RgColors.textBody)),
                  ],
                ),
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
        ),
        const SizedBox(height: RgSpace.s12),
        Semantics(
          button: true,
          child: RgPressable(
            onTap: () => showAiNoticeSheet(context),
            child: Padding(
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
                    child: KeepAllText(
                      '초록을 바탕으로 AI가 정리했어요. 논문 본문 전체를 반영하지는 않아요.',
                      perSentence: true, style: RgText.caption.copyWith(color: RgColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: RgSpace.s28),
      RgCard(
        padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s4),
        child: Column(
          children: [
            _InfoRow(
              label: '원문 출처',
              value: 'arXiv · ${p.id}',
              semanticsLabel: 'arXiv에서 원문 열기',
              onTap: () => launchUrl(Uri.parse(p.arxivUrl), mode: LaunchMode.externalApplication),
            ),
            // 토론·코드 링크가 있는 HF 논문 페이지(iOS QA P1). 데이터 출처 화면 문구와도 맞춘다.
            if (p.hfUrl.isNotEmpty)
              _InfoRow(
                label: '논문 페이지',
                value: 'Hugging Face',
                semanticsLabel: 'Hugging Face에서 논문 페이지 열기',
                onTap: () => launchUrl(Uri.parse(p.hfUrl), mode: LaunchMode.externalApplication),
              ),
            if (p.orgName != null) _InfoRow(label: '게시 조직', value: p.orgName!), // G8
            _InfoRow(label: '발행일', value: p.date, last: true),
          ],
        ),
      ),
    ];
  }
}

// 제목 블록 + AI 카드 모양.
class _PaperSkeleton extends StatelessWidget {
  const _PaperSkeleton();

  @override
  Widget build(BuildContext context) {
    return const RgSkeleton(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s12, RgSpace.gutterText, 0),
            child: Column(
              children: [
                RgBar(lineHeight: 24, widthFactor: 0.25),
                SizedBox(height: RgSpace.s14),
                RgBar(lineHeight: 35, widthFactor: 0.9),
                SizedBox(height: RgSpace.s8),
                RgBar(lineHeight: 22, widthFactor: 0.7),
                SizedBox(height: RgSpace.s10),
                RgBar(lineHeight: 20, widthFactor: 0.45),
              ],
            ),
          ),
          SizedBox(height: RgSpace.s24),
          RgCard(
            padding: EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
            child: Column(
              spacing: RgSpace.s4,
              children: [
                RgBar(lineHeight: 24, widthFactor: 0.3),
                SizedBox(height: RgSpace.s4),
                RgBar(lineHeight: 23),
                RgBar(lineHeight: 23),
                RgBar(lineHeight: 23, widthFactor: 0.6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.paper});
  final PaperDetail? paper;

  @override
  Widget build(BuildContext context) {
    final p = paper;
    return ChromeTextScale(
      child: SizedBox(
        height: RgSpace.topBar,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
          child: Row(
            spacing: RgSpace.s8,
            children: [
              RgBackButton(onTap: () => context.pop()),
              const Spacer(),
              if (p != null) ...[
                // AI 카드 글자 크기(S03과 같은 4단계). 카드가 있을 때만(iOS QA)
                if (p.ready)
                  RgCircleButton(semanticLabel: '글자 크기', text: '가', onTap: () => showTextSizeSheet(context)),
                RgCircleButton(
                  semanticLabel: '공유',
                  icon: 'share',
                  onTap: () => SharePlus.instance.share(ShareParams(text: '${p.title}\n${p.hfUrl}')),
                ),
                ValueListenableBuilder(
                  valueListenable: bookmarks,
                  builder: (_, saved, _) =>
                      RgBookmarkButton(saved: saved.containsKey(p.id), onTap: () => toggleBookmark(p.id, p.title)),
                ),
              ],
            ],
          ),
        ),
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
    void open() => showEvidenceSheet(context, paper: paper, pointIndex: index, sentenceId: point.evidenceIds.first);
    // 번호는 본문과 같은 15pt·같은 행간, 간격 8(피드백: 번호가 작고 내용과 너무 떨어져 보였다)
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: RgSpace.s8,
      children: [
        Text(
          '$index',
          style: RgText.bodySummary.copyWith(fontWeight: FontWeight.w600, color: RgColors.textSecondary),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KeepAllText(point.claim, style: RgText.bodySummary),
              Semantics(
                button: true,
                label: '원문 근거, 초록 $n번째 문장',
                excludeSemantics: true,
                onTap: open, // excludeSemantics가 하위의 탭 동작까지 지우므로 직접 넘긴다
                child: RgPressable(
                  onTap: open,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 36),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: RgSpace.s2,
                      children: [
                        Flexible(child: Text('원문 근거 · 초록 $n번째 문장', style: linkStyle)),
                        const RgIcon('chevron-right', size: 14, color: RgColors.textSecondary),
                      ],
                    ),
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
  const _InfoRow({required this.label, required this.value, this.onTap, this.semanticsLabel, this.last = false});
  final String label;
  final String value;
  final VoidCallback? onTap; // 있으면 외부 링크: 값 옆에 ↗(iOS QA P1)
  final String? semanticsLabel;
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
          Expanded(
            child: Text(value, textAlign: TextAlign.end, style: RgText.bodySmall),
          ),
          if (onTap != null)
            Padding(
              // bodySmall 첫 줄(행간 21) 가운데
              padding: EdgeInsets.only(top: (MediaQuery.textScalerOf(context).scale(21) - 14) / 2),
              child: const RgIcon('arrow-up-right', size: 14, color: RgColors.textTertiary),
            ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: RgColors.dividerCard)),
      ),
      child: onTap == null
          ? row
          : Semantics(
              link: true,
              label: semanticsLabel,
              excludeSemantics: semanticsLabel != null,
              onTap: onTap, // excludeSemantics가 하위의 탭 동작까지 지우므로 직접 넘긴다
              child: RgPressable(onTap: onTap, child: row),
            ),
    );
  }
}

// 요약을 문장 단위 문단으로. 한글·닫는 괄호 뒤 마침표 다음 공백에서만 나눠 「3.0배」 같은 수치는 건드리지 않는다.
List<String> summaryParagraphs(String s) =>
    s.trim().split(RegExp(r'(?<=[가-힣)\]][.!?])\s+')).where((p) => p.isNotEmpty).toList();
